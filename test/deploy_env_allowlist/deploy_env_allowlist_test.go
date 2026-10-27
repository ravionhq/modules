package deployenv

import (
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

func readEnvExpression(t *testing.T, path string) string {
	t.Helper()

	source, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("read %s: %v", path, err)
	}

	lines := strings.Split(string(source), "\n")
	var expressions []string
	for index, line := range lines {
		if strings.TrimSpace(line) != "env: >-" {
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

		scalar := strings.Join(scalarLines, " ")
		if strings.Contains(scalar, "deploy_environment_variable_names") {
			expressions = append(expressions, scalar)
		}
	}

	if len(expressions) != 1 {
		t.Fatalf("found %d deploy env expressions in %s, want exactly one", len(expressions), path)
	}

	template := strings.TrimSpace(expressions[0])
	if !strings.HasPrefix(template, "<<") || !strings.HasSuffix(template, ">>") {
		t.Fatalf("env expression in %s is not wrapped in << >>: %q", path, template)
	}
	expression := strings.TrimSpace(strings.TrimSuffix(strings.TrimPrefix(template, "<<"), ">>"))
	rawTransform := `, {"name": #.name, "value": string(#.value)})`
	normalizedTransform := `, true ? {"name": #.name, "value": string(#.value)} : nil)`
	if strings.Count(expression, rawTransform) != 1 {
		t.Fatalf("found unexpected map transform in %s", path)
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
