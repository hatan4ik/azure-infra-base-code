# Testing Framework

Comprehensive testing suite for validating scripts, Terraform modules, and configuration.

## Test Structure

```
tests/
├── unit/                    # Bats unit tests for bash scripts
│   ├── test_bootstrap.bats
│   └── test_network.bats
├── integration/             # Integration tests
│   └── test_terraform.sh
└── README.md               # This file
```

## Prerequisites

### Install Bats (Bash Automated Testing System)

**macOS:**
```bash
brew install bats-core
```

**Ubuntu/Debian:**
```bash
sudo apt-get install -y bats
```

**Manual:**
```bash
git clone https://github.com/bats-core/bats-core.git
cd bats-core
sudo ./install.sh /usr/local
```

### Install Terraform

```bash
# macOS
brew install terraform

# Ubuntu/Debian
wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt-get update && sudo apt-get install terraform
```

## Running Tests

### Run All Tests

```bash
# From repository root
./tests/run-all-tests.sh
```

### Run Unit Tests Only

```bash
# Run all Bats tests
bats tests/unit/*.bats

# Run specific test file
bats tests/unit/test_bootstrap.bats
```

### Run Integration Tests

```bash
# Terraform validation
bash tests/integration/test_terraform.sh
```

### Run Configuration Validation

```bash
# Check for placeholder values
bash scripts/validate-config.sh
```

## Test Coverage

### Unit Tests (Bats)

**test_bootstrap.bats:**
- Shebang validation
- Error handling (`set -euo pipefail`)
- Input validation functions
- Idempotent resource creation
- Tag merge functionality
- Diagnostic settings
- RBAC assignments

**test_network.bats:**
- Script structure validation
- CIDR calculation logic
- VNet creation idempotency
- Subnet provisioning
- DNS zone creation
- Private endpoint policies

### Integration Tests

**test_terraform.sh:**
- Terraform formatting validation
- Module initialization
- Configuration validation
- Syntax checking across all modules
- Environment configuration validation

### Configuration Tests

**validate-config.sh:**
- Placeholder detection
- Resource naming validation
- Required value checks
- Example/dummy value detection

## CI/CD Integration

Tests run automatically in `pipelines/script-validation.yaml`:

```yaml
stages:
- stage: ScriptValidation
  jobs:
  - job: ShellCheck        # Linting
  - job: ScriptSyntax      # Syntax validation
  - job: BatsTests         # Unit tests
  - job: TerraformTests    # Terraform validation
  - job: ConfigValidation  # Configuration checks
```

## Writing New Tests

### Bats Test Example

```bash
#!/usr/bin/env bats

setup() {
  # Run before each test
  export TEST_VAR="value"
}

teardown() {
  # Run after each test
  unset TEST_VAR
}

@test "description of test" {
  # Test commands
  run command_to_test
  [ "$status" -eq 0 ]
  [ "$output" = "expected output" ]
}

@test "check file contains pattern" {
  grep -q "pattern" file.sh
}
```

### Integration Test Example

```bash
#!/usr/bin/env bash
set -euo pipefail

FAILED=0

# Test something
if ! some_command; then
  echo "❌ Test failed"
  ((FAILED++))
else
  echo "✓ Test passed"
fi

exit $FAILED
```

## Test Best Practices

1. **Isolation**: Tests should not depend on each other
2. **Idempotency**: Tests should be repeatable
3. **Fast**: Unit tests should run quickly
4. **Clear**: Test names should describe what they validate
5. **Comprehensive**: Cover happy path and error cases

## Troubleshooting

### Bats Not Found

```bash
# Verify installation
which bats

# Check version
bats --version
```

### Terraform Tests Fail

```bash
# Ensure Terraform is installed
terraform version

# Check module syntax manually
cd terraform/modules/bootstrap
terraform init -backend=false
terraform validate
```

### Permission Denied

```bash
# Make test scripts executable
chmod +x tests/unit/*.bats
chmod +x tests/integration/*.sh
```

## Continuous Improvement

Add tests when:
- Creating new scripts
- Adding new features
- Fixing bugs
- Refactoring code

Update tests when:
- Changing script behavior
- Modifying module structure
- Updating requirements

## Support

For test failures:
1. Check test output for specific error
2. Run failing test individually
3. Verify prerequisites installed
4. Check script syntax manually

---

**Engineering Board Approved**  
**Version:** 1.0  
**Last Updated:** 2024-01-15