package deployenv

import (
	"fmt"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"

	"github.com/expr-lang/expr"
)

func TestDeployEnvironmentVariableAllowlist(t *testing.T) {
	commonExpression := readEnvExpression(t, filepath.Join("..", "..", "partials", "deploy", "eks-workload-helm-values-common.yml"))
	webExpression := readEnvExpression(t, filepath.Join("..", "..", "compute", "eks_service", "rvn-eks-web-definition.yml"))

	tests := []struct {
		name        string
		expression  string
		moduleInput map[string]interface{}
		deployInput map[string]interface{}
		want        []interface{}
	}{
		{
			name:        "allowlist unset",
			expression:  commonExpression,
			moduleInput: moduleInput(envEntry("MODULE_VALUE", "module")),
			deployInput: map[string]interface{}{
				"environment_variables": []interface{}{envEntry("RUNNER_VERSION", "abc123def456")},
			},
			want: []interface{}{envEntry("MODULE_VALUE", "module")},
		},
		{
			name: "allowlist empty",
			moduleInput: withAllowlist(
				moduleInput(envEntry("MODULE_VALUE", "module")),
				[]interface{}{},
			),
			deployInput: map[string]interface{}{
				"environment_variables": []interface{}{envEntry("RUNNER_VERSION", "abc123def456")},
			},
			expression: commonExpression,
			want:       []interface{}{envEntry("MODULE_VALUE", "module")},
		},
		{
			name: "allowlisted RUNNER_VERSION is kept and HTTPS_PROXY is dropped",
			moduleInput: withAllowlist(
				moduleInput(envEntry("MODULE_VALUE", "module")),
				[]interface{}{"RUNNER_VERSION"},
			),
			deployInput: map[string]interface{}{
				"environment_variables": []interface{}{
					envEntry("RUNNER_VERSION", "abc123def456"),
					envEntry("HTTPS_PROXY", "proxy"),
				},
			},
			expression: commonExpression,
			want: []interface{}{
				envEntry("MODULE_VALUE", "module"),
				envEntry("RUNNER_VERSION", "abc123def456"),
			},
		},
		{
			name: "module environment variable collision keeps the module value",
			moduleInput: withAllowlist(
				moduleInput(
					envEntry("MODULE_VALUE", "module"),
					envEntry("SHARED_VALUE", "module"),
				),
				[]interface{}{"SHARED_VALUE"},
			),
			deployInput: map[string]interface{}{
				"environment_variables": []interface{}{envEntry("SHARED_VALUE", "deploy")},
			},
			expression: commonExpression,
			want: []interface{}{
				envEntry("MODULE_VALUE", "module"),
				envEntry("SHARED_VALUE", "module"),
			},
		},
		{
			name: "module secret collision is dropped",
			moduleInput: withAllowlist(
				map[string]interface{}{
					"environment_variables": []interface{}{envEntry("MODULE_VALUE", "module")},
					"secrets":               []interface{}{map[string]interface{}{"name": "SECRET_VALUE"}},
				},
				[]interface{}{"SECRET_VALUE"},
			),
			deployInput: map[string]interface{}{
				"environment_variables": []interface{}{envEntry("SECRET_VALUE", "deploy")},
			},
			expression: commonExpression,
			want:       []interface{}{envEntry("MODULE_VALUE", "module")},
		},
		{
			name: "value_from without a plain value is dropped",
			moduleInput: withAllowlist(
				moduleInput(envEntry("MODULE_VALUE", "module")),
				[]interface{}{"SECRET_VALUE"},
			),
			deployInput: map[string]interface{}{
				"environment_variables": []interface{}{
					map[string]interface{}{
						"name":       "SECRET_VALUE",
						"value_from": map[string]interface{}{"secret_key_ref": "secret"},
					},
				},
			},
			expression: commonExpression,
			want:       []interface{}{envEntry("MODULE_VALUE", "module")},
		},
		{
			name: "missing deploy environment_variables is safe",
			moduleInput: withAllowlist(
				moduleInput(envEntry("MODULE_VALUE", "module")),
				[]interface{}{"RUNNER_VERSION"},
			),
			deployInput: map[string]interface{}{},
			expression:  commonExpression,
			want:        []interface{}{envEntry("MODULE_VALUE", "module")},
		},
		{
			name: "web PORT cannot be overridden",
			moduleInput: withAllowlist(
				map[string]interface{}{
					"container_port":        8080,
					"environment_variables": []interface{}{envEntry("MODULE_VALUE", "module")},
				},
				[]interface{}{"PORT"},
			),
			deployInput: map[string]interface{}{
				"environment_variables": []interface{}{envEntry("PORT", "9090")},
			},
			expression: webExpression,
			want: []interface{}{
				envEntry("PORT", "8080"),
				envEntry("MODULE_VALUE", "module"),
			},
		},
		{
			name: "non-string values are stringified",
			moduleInput: withAllowlist(
				moduleInput(envEntry("MODULE_VALUE", "module")),
				[]interface{}{"RETRY_COUNT"},
			),
			deployInput: map[string]interface{}{
				"environment_variables": []interface{}{envEntry("RETRY_COUNT", 3)},
			},
			expression: commonExpression,
			want: []interface{}{
				envEntry("MODULE_VALUE", "module"),
				envEntry("RETRY_COUNT", "3"),
			},
		},
	}

	for _, testCase := range tests {
		t.Run(testCase.name, func(t *testing.T) {
			context := map[string]interface{}{
				"module": map[string]interface{}{"input": testCase.moduleInput},
				"deploy": map[string]interface{}{"input": testCase.deployInput},
			}

			program, err := expr.Compile(testCase.expression, expr.Env(context))
			if err != nil {
				t.Fatalf("compile env expression: %v", err)
			}

			result, err := expr.Run(program, context)
			if err != nil {
				t.Fatalf("evaluate env expression: %v", err)
			}

			actual, ok := result.([]interface{})
			if !ok {
				t.Fatalf("env expression returned %T, want []interface{}", result)
			}
			if !reflect.DeepEqual(actual, testCase.want) {
				t.Fatalf("env expression result = %#v, want %#v", actual, testCase.want)
			}
		})
	}
}

func TestECSDeployEnvironmentVariableAllowlist(t *testing.T) {
	type fixture struct {
		name                  string
		allowlist             []interface{}
		setAllowlist          bool
		moduleEnvironment     []interface{}
		secrets               []interface{}
		deployEnvironment     []interface{}
		omitDeployEnvironment bool
		wantDeployEnvironment []interface{}
	}

	workloads := []struct {
		name        string
		path        string
		portValue   int
		portInputID string
	}{
		{
			name:        "web",
			path:        filepath.Join("..", "..", "compute", "ecs_service", "rvn-ecs-web-definition.yml"),
			portValue:   8080,
			portInputID: "container_port",
		},
		{
			name: "worker",
			path: filepath.Join("..", "..", "compute", "ecs_service", "rvn-ecs-worker-definition.yml"),
		},
		{
			name:        "nlb",
			path:        filepath.Join("..", "..", "compute", "ecs_service", "rvn-ecs-nlb-definition.yml"),
			portValue:   3000,
			portInputID: "listeners",
		},
	}
	fixtures := []fixture{
		{
			name: "allowlist unset",
			deployEnvironment: []interface{}{
				envEntry("RUNNER_VERSION", "abc123def456"),
			},
		},
		{
			name:         "allowlist empty",
			allowlist:    []interface{}{},
			setAllowlist: true,
			deployEnvironment: []interface{}{
				envEntry("RUNNER_VERSION", "abc123def456"),
			},
		},
		{
			name:         "allowlisted value is kept and unlisted value is dropped",
			allowlist:    []interface{}{"RUNNER_VERSION"},
			setAllowlist: true,
			deployEnvironment: []interface{}{
				envEntry("RUNNER_VERSION", "abc123def456"),
				envEntry("HTTPS_PROXY", "proxy"),
			},
			wantDeployEnvironment: []interface{}{envEntry("RUNNER_VERSION", "abc123def456")},
		},
		{
			name:         "module environment variable collision keeps the module value",
			allowlist:    []interface{}{"SHARED_VALUE"},
			setAllowlist: true,
			moduleEnvironment: []interface{}{
				envEntry("MODULE_VALUE", "module"),
				envEntry("SHARED_VALUE", "module"),
			},
			deployEnvironment:     []interface{}{envEntry("SHARED_VALUE", "deploy")},
			wantDeployEnvironment: []interface{}{},
		},
		{
			name:         "module secret collision is dropped",
			allowlist:    []interface{}{"SECRET_VALUE"},
			setAllowlist: true,
			secrets:      []interface{}{map[string]interface{}{"name": "SECRET_VALUE"}},
			deployEnvironment: []interface{}{
				envEntry("SECRET_VALUE", "deploy"),
			},
		},
		{
			name:         "value_from without a plain value is dropped",
			allowlist:    []interface{}{"SECRET_VALUE"},
			setAllowlist: true,
			deployEnvironment: []interface{}{
				map[string]interface{}{
					"name":       "SECRET_VALUE",
					"value_from": map[string]interface{}{"secret_key_ref": "secret"},
				},
			},
		},
		{
			name:                  "missing deploy environment_variables is safe",
			allowlist:             []interface{}{"RUNNER_VERSION"},
			setAllowlist:          true,
			omitDeployEnvironment: true,
		},
		{
			name:         "non-string values are stringified",
			allowlist:    []interface{}{"RETRY_COUNT"},
			setAllowlist: true,
			deployEnvironment: []interface{}{
				envEntry("RETRY_COUNT", 3),
			},
			wantDeployEnvironment: []interface{}{envEntry("RETRY_COUNT", "3")},
		},
	}

	for _, workload := range workloads {
		expressions := readAppContainerEnvironmentExpressions(t, workload.path)
		if len(expressions) != 2 {
			t.Fatalf("%s has %d app-container environment expressions, want 2", workload.name, len(expressions))
		}

		workloadFixtures := append([]fixture{}, fixtures...)
		if workload.portValue != 0 {
			workloadFixtures = append(workloadFixtures, fixture{
				name:         "reserved PORT cannot be overridden",
				allowlist:    []interface{}{"PORT"},
				setAllowlist: true,
				deployEnvironment: []interface{}{
					envEntry("PORT", "9090"),
				},
			})
		}

		for expressionIndex, expression := range expressions {
			for _, fixture := range workloadFixtures {
				t.Run(fmt.Sprintf("%s/app_variant_%d/%s", workload.name, expressionIndex+1, fixture.name), func(t *testing.T) {
					moduleEnvironment := fixture.moduleEnvironment
					if moduleEnvironment == nil {
						moduleEnvironment = []interface{}{envEntry("MODULE_VALUE", "module")}
					}

					input := map[string]interface{}{
						"environment_variables": moduleEnvironment,
					}
					switch workload.portInputID {
					case "container_port":
						input["container_port"] = workload.portValue
					case "listeners":
						input["listeners"] = []interface{}{
							map[string]interface{}{"container_port": workload.portValue},
						}
					}
					if fixture.setAllowlist {
						input["deploy_environment_variable_names"] = fixture.allowlist
					}
					if fixture.secrets != nil {
						input["secrets"] = fixture.secrets
					}

					deployInput := map[string]interface{}{}
					if !fixture.omitDeployEnvironment {
						deployInput["environment_variables"] = fixture.deployEnvironment
					}

					context := map[string]interface{}{
						"module": map[string]interface{}{"input": input},
						"deploy": map[string]interface{}{"input": deployInput},
					}
					program, err := expr.Compile(expression, expr.Env(context))
					if err != nil {
						t.Fatalf("compile %s app-container environment: %v", workload.name, err)
					}

					result, err := expr.Run(program, context)
					if err != nil {
						t.Fatalf("evaluate %s app-container environment: %v", workload.name, err)
					}

					actual, ok := result.([]interface{})
					if !ok {
						t.Fatalf("%s app-container environment returned %T, want []interface{}", workload.name, result)
					}
					want := make([]interface{}, 0, len(moduleEnvironment)+len(fixture.wantDeployEnvironment)+1)
					if workload.portValue != 0 {
						want = append(want, envEntry("PORT", fmt.Sprint(workload.portValue)))
					}
					want = append(want, moduleEnvironment...)
					want = append(want, fixture.wantDeployEnvironment...)
					if !reflect.DeepEqual(actual, want) {
						t.Fatalf("%s app-container environment = %#v, want %#v", workload.name, actual, want)
					}
				})
			}
		}
	}
}

func readEnvExpression(t *testing.T, path string) string {
	t.Helper()

	expressions := readTemplateExpressions(t, path, "env")
	var allowlistExpressions []string
	for _, expression := range expressions {
		if strings.Contains(expression, "deploy_environment_variable_names") {
			allowlistExpressions = append(allowlistExpressions, expression)
		}
	}

	if len(allowlistExpressions) != 1 {
		t.Fatalf("found %d deploy env expressions in %s, want exactly one", len(allowlistExpressions), path)
	}

	return normalizeMapTransform(t, path, allowlistExpressions[0])
}

func readTemplateExpressions(t *testing.T, path string, key string) []string {
	t.Helper()

	source, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("read %s: %v", path, err)
	}

	lines := strings.Split(string(source), "\n")
	var expressions []string
	for index, line := range lines {
		if strings.TrimSpace(line) != key+": >-" {
			continue
		}

		indent := len(line) - len(strings.TrimLeft(line, " \t"))
		var scalarLines []string
		for _, scalarLine := range lines[index+1:] {
			if strings.TrimSpace(scalarLine) == "" {
				continue
			}
			scalarIndent := len(scalarLine) - len(strings.TrimLeft(scalarLine, " \t"))
			if scalarIndent <= indent {
				break
			}
			scalarLines = append(scalarLines, strings.TrimSpace(scalarLine))
		}

		template := strings.Join(scalarLines, " ")
		if !strings.HasPrefix(template, "<<") || !strings.HasSuffix(template, ">>") {
			t.Fatalf("%s expression in %s is not wrapped in << >>: %q", key, path, template)
		}
		expression := strings.TrimSpace(strings.TrimSuffix(strings.TrimPrefix(template, "<<"), ">>"))
		expressions = append(expressions, expression)
	}
	return expressions
}

func readAppContainerEnvironmentExpressions(t *testing.T, path string) []string {
	t.Helper()

	templates := readTemplateExpressions(t, path, "container_definitions")
	if len(templates) != 1 {
		t.Fatalf("found %d container_definitions expressions in %s, want exactly one", len(templates), path)
	}

	const property = `"environment":`
	expression := templates[0]
	var environments []string
	for offset := 0; offset < len(expression); {
		propertyOffset := strings.Index(expression[offset:], property)
		if propertyOffset < 0 {
			break
		}
		valueStart := offset + propertyOffset + len(property)
		for valueStart < len(expression) && (expression[valueStart] == ' ' || expression[valueStart] == '\t') {
			valueStart++
		}
		value, nextOffset, err := readExpressionValue(expression, valueStart)
		if err != nil {
			t.Fatalf("extract app-container environment from %s: %v", path, err)
		}
		if strings.Contains(value, "module.input.environment_variables") &&
			!strings.Contains(value, "FIRELENS_CONFIG_CONTENT") {
			environments = append(environments, normalizeMapTransform(t, path, value))
		}
		offset = nextOffset
	}
	return environments
}

func readExpressionValue(source string, start int) (string, int, error) {
	depth := 0
	var quote byte
	escaped := false
	for index := start; index < len(source); index++ {
		character := source[index]
		if quote != 0 {
			if escaped {
				escaped = false
				continue
			}
			if character == '\\' {
				escaped = true
				continue
			}
			if character == quote {
				quote = 0
			}
			continue
		}

		switch character {
		case '"', '\'':
			quote = character
		case '(', '[', '{':
			depth++
		case ')', ']', '}':
			depth--
			if depth < 0 {
				return "", index, fmt.Errorf("unbalanced delimiter at byte %d", index)
			}
		case ',':
			if depth == 0 {
				return strings.TrimSpace(source[start:index]), index + 1, nil
			}
		}
	}
	return "", len(source), fmt.Errorf("unterminated expression value beginning at byte %d", start)
}

func normalizeMapTransform(t *testing.T, path string, expression string) string {
	t.Helper()

	rawTransform := `, {"name": #.name, "value": string(#.value)})`
	normalizedTransform := `, true ? {"name": #.name, "value": string(#.value)} : nil)`
	if strings.Count(expression, rawTransform) != 1 {
		t.Fatalf("found unexpected map transform in %s: %s", path, expression)
	}
	return strings.Replace(expression, rawTransform, normalizedTransform, 1)
}

func moduleInput(environmentVariables ...interface{}) map[string]interface{} {
	return map[string]interface{}{
		"environment_variables": environmentVariables,
	}
}

func withAllowlist(input map[string]interface{}, names []interface{}) map[string]interface{} {
	input["deploy_environment_variable_names"] = names
	return input
}

func envEntry(name string, value interface{}) map[string]interface{} {
	return map[string]interface{}{
		"name":  name,
		"value": value,
	}
}
