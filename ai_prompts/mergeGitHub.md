# GitHub Merge Workflow - Professional Template

**Repository**: [REPOSITORY_NAME]
**Target Branch**: origin/main
**Current Branch**: main
**Workflow Version**: 1.0 (Enhanced Generic Template)

---

## Workflow Overview and Usage Instructions

### Purpose
This workflow provides a systematic approach to organizing, committing, and merging code changes to the main branch with professional documentation and quality assurance.

### Prerequisites
- Git repository with main branch as default
- Node.js project with npm/yarn package management
- CI/CD pipeline configured
- Access to push to origin/main

### Usage Instructions
1. **Customize placeholders**: Replace all [PLACEHOLDER] values with project-specific information
2. **Adapt categories**: Modify commit categories based on your project structure
3. **Configure tools**: Ensure test runners, linters, and build tools are properly configured
4. **Review team standards**: Align commit message format with team conventions

### Workflow Phases
1. **Analysis Phase**: Repository status verification and change categorization
2. **Commit Phase**: Systematic organization of changes into logical commits
3. **Verification Phase**: Quality assurance and testing
4. **Merge Phase**: Push to remote and deployment verification
5. **Monitoring Phase**: Post-merge validation and monitoring

---

## Pre-Merge Analysis and Preparation

### 1. Repository Status Verification
- [ ] Confirm current branch is main and up-to-date with origin/main
- [ ] Verify no staged changes exist (git diff --cached should be empty)
- [ ] Confirm working directory status and identify all changes
- [ ] Check remote connectivity: git remote -v
- [ ] Document current version numbers (VERSION file, package.json, CHANGELOG.md)

### 2. Backup and Safety Measures
- [ ] Create backup branch: git checkout -b backup/pre-merge-$(date +%Y%m%d-%H%M%S)
- [ ] Return to main: git checkout main
- [ ] Run test suite to establish baseline: npm test
- [ ] Run linting checks: npm run lint
- [ ] Run TypeScript compilation check: npx tsc --noEmit

### 3. Change Analysis and Categorization
- [ ] Analyze modified files: git diff --name-only
- [ ] Analyze untracked files: git status --porcelain | grep "^??"
- [ ] Analyze deleted files: git status --porcelain | grep "^.D"
- [ ] Count total changes: git status --porcelain | wc -l
- [ ] Categorize changes using file patterns:
  - **Configuration**: *.json, *.js, *.ts, *.yml, *.yaml, package*, *.config.*
  - **Source Code**: src/, lib/, app/, components/, pages/, utils/
  - **Tests**: *test*, *spec*, __tests__/, tests/
  - **Documentation**: *.md, docs/, README*, CHANGELOG*
  - **Logs/Reports**: logs/, reports/, *.log, test-logs/
  - **Scripts**: scripts/, bin/, *.sh, *.ps1
- [ ] Determine commit grouping strategy based on change types
- [ ] Plan semantic versioning increment (patch/minor/major)
- [ ] Estimate total number of commits needed (recommended: 3-8 commits)
- [ ] Document change summary for reference

---

## Staged Commit Workflow

### 4. Configuration and Build System Changes
**Commit Type**: chore(config) or chore(build)
**Target Files**: Configuration files, build scripts, CI/CD workflows, package management
**Priority**: High (affects build and deployment processes)

**Identification Process**:
```bash
# Identify configuration files to commit
git status --porcelain | grep -E "\.(json|js|ts|yml|yaml|toml|ini|env)$|package-lock|yarn.lock|\.config\."
```

**Validation Checklist**:
- [ ] Verify configuration syntax is valid
- [ ] Check for sensitive data exposure
- [ ] Validate dependency versions are compatible
- [ ] Ensure CI/CD configuration is correct

**Commit Process**:
```bash
# Add configuration files
git add [CONFIGURATION_FILES]

# Commit with structured professional message
git commit -m "chore(config): Update build system and configuration files

Summary: [ONE_LINE_SUMMARY_OF_CHANGES]

Changes:
- [SPECIFIC_CONFIGURATION_CHANGE_1]
- [SPECIFIC_DEPENDENCY_UPDATE_2]
- [SPECIFIC_BUILD_IMPROVEMENT_3]
- [SPECIFIC_CI_CD_ENHANCEMENT_4]

Impact:
- Build: [DESCRIBE_BUILD_IMPACT]
- Dependencies: [DESCRIBE_DEPENDENCY_IMPACT]
- CI/CD: [DESCRIBE_PIPELINE_IMPACT]

Breaking Changes: [NONE_OR_DESCRIBE_BREAKING_CHANGES]
Migration Notes: [MIGRATION_INSTRUCTIONS_IF_NEEDED]
CHANGELOG: [DESCRIBE_CHANGELOG_IMPACT]"

# Verify commit was created successfully
git log --oneline -1
```

### 5. Test Infrastructure and Quality Assurance
**Commit Type**: test(infrastructure) or test(coverage)
**Target Files**: Test files, test utilities, mocks, test configuration
**Priority**: High (critical for code quality and reliability)

**Identification Process**:
```bash
# Identify test-related files
git status --porcelain | grep -E "__tests__|\.test\.|\.spec\.|test/|tests/|mock|fixture"
```

**Validation Checklist**:
- [ ] Verify all new tests pass locally
- [ ] Check test coverage impact
- [ ] Validate mock implementations are accurate
- [ ] Ensure test utilities are properly documented

**Commit Process**:
```bash
# Add test files
git add [TEST_FILES_AND_DIRECTORIES]

# Commit with structured professional message
git commit -m "test(infrastructure): Enhance test infrastructure and coverage

Summary: [ONE_LINE_SUMMARY_OF_TEST_CHANGES]

Test Additions:
- [SPECIFIC_NEW_TEST_FILE_1]
- [SPECIFIC_NEW_TEST_FILE_2]
- [SPECIFIC_TEST_UTILITY_3]

Improvements:
- [DESCRIBE_COVERAGE_IMPROVEMENTS]
- [DESCRIBE_MOCK_ENHANCEMENTS]
- [DESCRIBE_TEST_RELIABILITY_IMPROVEMENTS]

Metrics:
- Coverage: [BEFORE_PERCENTAGE] → [AFTER_PERCENTAGE]
- Test Count: [BEFORE_COUNT] → [AFTER_COUNT]
- Test Categories: [LIST_TEST_CATEGORIES]

Quality Impact: [DESCRIBE_QUALITY_IMPROVEMENTS]
CHANGELOG: [DESCRIBE_CHANGELOG_IMPACT]"

# Verify commit and run tests
git log --oneline -1
npm test
```

### 6. Security and Authentication Features
**Commit Type**: feat(security) or fix(security)
**Target Files**: Security modules, authentication systems, middleware

**Process**:
```bash
# Identify security-related files
git status --porcelain | grep -E "security|auth|csrf|rbac|middleware"

# Add security files
git add [SECURITY_FILES]

# Commit with professional message
git commit -m "feat(security): Enhance security framework and authentication

- [DESCRIBE_SECURITY_ENHANCEMENTS]
- [DESCRIBE_AUTHENTICATION_IMPROVEMENTS]
- [DESCRIBE_AUTHORIZATION_FEATURES]
- [DESCRIBE_SECURITY_MONITORING]

Security: [DESCRIBE_SECURITY_COMPLIANCE]
Breaking: [NONE_OR_DESCRIBE_BREAKING_CHANGES]
CHANGELOG: [DESCRIBE_CHANGELOG_IMPACT]"
```

### 7. API and Service Layer Enhancements
**Commit Type**: feat(api) or refactor(api)
**Target Files**: API routes, service modules, data models

**Process**:
```bash
# Identify API and service files
git status --porcelain | grep -E "api/|service|model/|lib/"

# Add API and service files
git add [API_AND_SERVICE_FILES]

# Commit with professional message
git commit -m "feat(api): Enhance API routes and service layer

- [DESCRIBE_API_IMPROVEMENTS]
- [DESCRIBE_SERVICE_ENHANCEMENTS]
- [DESCRIBE_DATA_MODEL_CHANGES]
- [DESCRIBE_INTEGRATION_IMPROVEMENTS]

Performance: [DESCRIBE_PERFORMANCE_IMPROVEMENTS]
Features: [DESCRIBE_NEW_FEATURES]
Breaking: [NONE_OR_DESCRIBE_BREAKING_CHANGES]
CHANGELOG: [DESCRIBE_CHANGELOG_IMPACT]"
```

### 8. User Interface and Component Updates
**Commit Type**: feat(ui) or refactor(ui)
**Target Files**: React components, pages, styles, UI utilities

**Process**:
```bash
# Identify UI-related files
git status --porcelain | grep -E "components/|pages/|app/.*page\.|\.css|\.scss|\.module\."

# Add UI files
git add [UI_COMPONENT_FILES]

# Commit with professional message
git commit -m "feat(ui): Enhance user interface components and user experience

- [DESCRIBE_COMPONENT_IMPROVEMENTS]
- [DESCRIBE_PAGE_ENHANCEMENTS]
- [DESCRIBE_STYLING_UPDATES]
- [DESCRIBE_ACCESSIBILITY_IMPROVEMENTS]

UX: [DESCRIBE_USER_EXPERIENCE_IMPROVEMENTS]
Performance: [DESCRIBE_PERFORMANCE_OPTIMIZATIONS]
Breaking: [NONE_OR_DESCRIBE_BREAKING_CHANGES]
CHANGELOG: [DESCRIBE_CHANGELOG_IMPACT]"
```

### 9. Feature Implementation and Business Logic
**Commit Type**: feat(feature-name) or feat(core)
**Target Files**: Core business logic, new features, utilities

**Process**:
```bash
# Identify feature and business logic files
git status --porcelain | grep -E "src/lib/|src/utils/|src/core/|features/"

# Add feature files
git add [FEATURE_FILES]

# Commit with professional message
git commit -m "feat([FEATURE_NAME]): Implement [FEATURE_DESCRIPTION]

- [DESCRIBE_FEATURE_IMPLEMENTATION]
- [DESCRIBE_BUSINESS_LOGIC_CHANGES]
- [DESCRIBE_UTILITY_ADDITIONS]
- [DESCRIBE_INTEGRATION_POINTS]

Features: [DESCRIBE_NEW_CAPABILITIES]
Performance: [DESCRIBE_PERFORMANCE_IMPACT]
Breaking: [NONE_OR_DESCRIBE_BREAKING_CHANGES]
CHANGELOG: [DESCRIBE_CHANGELOG_IMPACT]"
```

### 10. Scripts and Automation Tools
**Commit Type**: chore(scripts) or feat(tooling)
**Target Files**: Build scripts, automation tools, utility scripts

**Process**:
```bash
# Identify script and tooling files
git status --porcelain | grep -E "scripts/|tools/|bin/|\.sh$|\.ps1$"

# Add script files
git add [SCRIPT_FILES]

# Commit with professional message
git commit -m "chore(scripts): Add automation scripts and development tools

- [DESCRIBE_SCRIPT_ADDITIONS]
- [DESCRIBE_AUTOMATION_IMPROVEMENTS]
- [DESCRIBE_DEVELOPMENT_TOOLS]
- [DESCRIBE_BUILD_ENHANCEMENTS]

Tooling: [DESCRIBE_TOOLING_IMPROVEMENTS]
Development: [DESCRIBE_DEVELOPER_EXPERIENCE]
CHANGELOG: [DESCRIBE_CHANGELOG_IMPACT]"
```

### 11. Documentation and Knowledge Management
**Commit Type**: docs(enhancement) or docs(update)
**Target Files**: Documentation files, README, guides, AI prompts

**Process**:
```bash
# Identify documentation files
git status --porcelain | grep -E "docs/|README|\.md$|\.txt$|prompts/"

# Add documentation files
git add [DOCUMENTATION_FILES]

# Commit with professional message
git commit -m "docs(enhancement): Update documentation and knowledge resources

- [DESCRIBE_DOCUMENTATION_UPDATES]
- [DESCRIBE_README_IMPROVEMENTS]
- [DESCRIBE_GUIDE_ADDITIONS]
- [DESCRIBE_KNOWLEDGE_RESOURCES]

Documentation: [DESCRIBE_COVERAGE_IMPROVEMENTS]
Maintenance: [DESCRIBE_MAINTENANCE_IMPROVEMENTS]
CHANGELOG: [DESCRIBE_CHANGELOG_IMPACT]"
```

### 12. Test Reports and Analysis Data
**Commit Type**: chore(reports) or chore(logs)
**Target Files**: Test logs, analysis reports, metrics, audit trails

**Process**:
```bash
# Identify report and log files
git status --porcelain | grep -E "test-logs/|reports/|\.log$|analysis|metrics"

# Add report files
git add [REPORT_AND_LOG_FILES]

# Commit with professional message
git commit -m "chore(reports): Add test execution logs and analysis reports

- [DESCRIBE_TEST_LOGS]
- [DESCRIBE_ANALYSIS_REPORTS]
- [DESCRIBE_METRICS_DATA]
- [DESCRIBE_AUDIT_TRAILS]

Testing: [DESCRIBE_TESTING_DOCUMENTATION]
Analysis: [DESCRIBE_ANALYSIS_IMPROVEMENTS]
Compliance: [DESCRIBE_COMPLIANCE_DOCUMENTATION]
CHANGELOG: [DESCRIBE_CHANGELOG_IMPACT]"
```

### 13. Version Management and Release Preparation
**Commit Type**: chore(release) or chore(version)
**Target Files**: VERSION file, CHANGELOG.md, package.json version

**Process**:
```bash
# Synchronize version numbers across files
# Update VERSION file, package.json, and CHANGELOG.md

# Add version-related files
git add VERSION CHANGELOG.md package.json

# Commit with professional message
git commit -m "chore(release): Update version and changelog for release

- Updated version from [OLD_VERSION] to [NEW_VERSION]
- Added comprehensive changelog entries for all changes
- Documented breaking changes and migration notes
- Updated semantic versioning for [PATCH/MINOR/MAJOR] release
- Synchronized version numbers across all configuration files

Version: [OLD_VERSION] → [NEW_VERSION] ([RELEASE_TYPE] release)
Features: [DESCRIBE_KEY_FEATURES]
Breaking: [NONE_OR_DESCRIBE_BREAKING_CHANGES]
CHANGELOG: [DESCRIBE_CHANGELOG_COMPLETENESS]"
```

---

## Branch Management and Merge Strategy

### 14. Pre-Merge Verification and Quality Assurance
**Critical Phase**: All checks must pass before proceeding to merge

**Code Quality Verification**:
- [ ] Run complete test suite: npm test
- [ ] Verify successful build: npm run build
- [ ] Check TypeScript compilation: npx tsc --noEmit
- [ ] Run linting checks: npm run lint
- [ ] Run security audit: npm audit
- [ ] Check for code formatting: npm run format:check (if available)

**Git and Commit Verification**:
- [ ] Verify all commits follow conventional commit format
- [ ] Check for any remaining unstaged changes: git status
- [ ] Validate commit message quality and completeness
- [ ] Ensure all version numbers are synchronized across files
- [ ] Verify no merge conflicts exist
- [ ] Check that all intended files are committed

**Documentation and Metadata Verification**:
- [ ] Ensure CHANGELOG.md is updated with all changes
- [ ] Verify README.md reflects any new features or changes
- [ ] Check that version numbers are consistent (VERSION, package.json, CHANGELOG.md)
- [ ] Validate that breaking changes are properly documented

**Final Pre-Push Checklist**:
- [ ] All automated tests pass
- [ ] Manual smoke testing completed (if applicable)
- [ ] Code review completed (if required by team process)
- [ ] All required approvals obtained
- [ ] Backup branch created and verified

### 15. Remote Repository Push
```bash
# Push all commits to remote main branch
git push origin main

# Verify push was successful
git log --oneline -5
```

### 16. Remote Merge Verification
- [ ] Check GitHub repository displays all new commits
- [ ] Verify CI/CD pipeline triggers successfully
- [ ] Confirm all automated status checks pass
- [ ] Validate deployment pipeline initiation
- [ ] Check for any merge conflicts or issues
- [ ] Verify branch protection rules are satisfied

---

## Post-Merge Verification and Monitoring

### 17. Deployment and Functionality Verification
- [ ] Verify staging environment deployment successful
- [ ] Run smoke tests on staging environment
- [ ] Check application health and status endpoints
- [ ] Validate new features function as expected
- [ ] Confirm no regressions in existing functionality
- [ ] Test critical user workflows end-to-end
- [ ] Verify database migrations completed successfully
- [ ] Check external service integrations

### 18. Monitoring and Performance Validation
- [ ] Monitor application metrics for initial 24-hour period
- [ ] Check error rates and exception logs
- [ ] Verify performance metrics within acceptable ranges
- [ ] Confirm security monitoring and alerting operational
- [ ] Validate logging and observability systems
- [ ] Check resource utilization and scaling behavior

---

## Emergency Rollback Procedures

### 19. Rollback Strategy (If Critical Issues Detected)

**Immediate Assessment**:
- [ ] Identify severity level: Critical, High, Medium, Low
- [ ] Determine impact scope: Production, Staging, Development
- [ ] Assess rollback urgency: Immediate, Scheduled, Next Release

**Rollback Options (Choose based on situation)**:

**Option 1: Selective Commit Revert (Recommended for isolated issues)**
```bash
# Identify problematic commit
git log --oneline -10

# Revert specific commit(s)
git revert [COMMIT_HASH] --no-edit

# Push revert commit
git push origin main
```

**Option 2: Complete Rollback to Previous Stable State**
```bash
# Reset to previous stable version (DESTRUCTIVE - use with caution)
git reset --hard [PREVIOUS_STABLE_COMMIT_HASH]

# Force push (requires team coordination)
git push origin main --force-with-lease
```

**Option 3: Emergency Hotfix Branch**
```bash
# Create hotfix branch from stable commit
git checkout [STABLE_COMMIT_HASH]
git checkout -b hotfix/emergency-fix-$(date +%Y%m%d-%H%M%S)

# Apply minimal critical fixes
# [APPLY_FIXES]

# Push hotfix branch
git push origin hotfix/emergency-fix-$(date +%Y%m%d-%H%M%S)

# Create pull request for review and merge
```

**Option 4: Backup Branch Restoration**
```bash
# Use pre-merge backup branch
git checkout backup/pre-merge-[TIMESTAMP]
git checkout -b restore/rollback-$(date +%Y%m%d-%H%M%S)

# Cherry-pick any critical fixes if needed
git cherry-pick [CRITICAL_FIX_COMMITS]

# Push restoration branch
git push origin restore/rollback-$(date +%Y%m%d-%H%M%S)
```

### 20. Incident Response and Recovery

**Immediate Response (0-15 minutes)**:
- [ ] Document critical issue in GitHub Issues with "critical" and "production" labels
- [ ] Notify stakeholders via established communication channels
- [ ] Implement chosen rollback strategy
- [ ] Verify rollback success and system stability

**Short-term Response (15 minutes - 2 hours)**:
- [ ] Conduct initial root cause analysis
- [ ] Document timeline of events and actions taken
- [ ] Communicate status updates to stakeholders
- [ ] Monitor system metrics for stability

**Medium-term Response (2-24 hours)**:
- [ ] Complete comprehensive root cause analysis
- [ ] Plan detailed remediation strategy
- [ ] Update monitoring and alerting based on incident
- [ ] Prepare incident report with lessons learned

**Long-term Response (1-7 days)**:
- [ ] Schedule post-incident review meeting with all stakeholders
- [ ] Update rollback procedures based on lessons learned
- [ ] Implement preventive measures to avoid similar issues
- [ ] Update team training and documentation
- [ ] Review and improve deployment and testing processes

---

## Success Metrics and Validation

### Quality Assurance Metrics
- **Commit Quality**: All commits follow conventional commit format
- **Test Coverage**: Maintain or improve existing test coverage percentage
- **Security**: No new security vulnerabilities introduced
- **Performance**: No degradation in key performance metrics
- **Documentation**: All changes properly documented
- **Compatibility**: No breaking changes without proper migration path

### Operational Metrics
- **Build Success**: All CI/CD pipeline stages pass successfully
- **Deployment**: Successful deployment to staging and production
- **Monitoring**: All health checks and monitoring systems operational
- **Rollback Readiness**: Clear rollback path available if needed

---

---

## Troubleshooting Guide

### Common Issues and Solutions

**Issue: Tests failing after organizing commits**
- Solution: Run tests after each commit group to isolate failures
- Prevention: Ensure test dependencies are committed in correct order

**Issue: Build failures due to missing dependencies**
- Solution: Verify package.json and lock files are committed together
- Prevention: Always commit dependency files as a group

**Issue: Merge conflicts during push**
- Solution: Pull latest changes, resolve conflicts, and re-push
- Prevention: Ensure branch is up-to-date before starting workflow

**Issue: CI/CD pipeline failures**
- Solution: Check pipeline logs, fix issues, and re-run
- Prevention: Test pipeline locally before pushing

**Issue: Version number inconsistencies**
- Solution: Manually synchronize all version files before final commit
- Prevention: Use automated version management tools

### Workflow Customization Guidelines

**For Small Teams (1-5 developers)**:
- Reduce commit groups to 3-5 categories
- Simplify verification steps
- Use shorter commit messages

**For Large Teams (10+ developers)**:
- Increase commit granularity
- Add mandatory code review steps
- Implement stricter verification processes

**For High-Risk Projects**:
- Add additional testing phases
- Require multiple approvals
- Implement staged deployment verification

---

## Workflow Metadata and Information

**Workflow Type**: Professional GitHub Merge Workflow Template
**Version**: 2.1 (Enhanced)
**Last Updated**: [UPDATE_DATE]
**Estimated Completion Time**: 1-4 hours (varies by change complexity and team size)
**Risk Level**: Variable (assess based on change scope, testing coverage, and team experience)
**Rollback Complexity**: Low to Medium (clear revert path with comprehensive backup strategy)
**Team Size Compatibility**: 1-50+ developers
**Project Type Compatibility**: Web applications, APIs, libraries, microservices

**Maintenance Notes**:
- Review and update workflow quarterly
- Adapt commit categories based on project evolution
- Update tooling commands as development stack changes
- Gather team feedback and incorporate improvements

**Support and Documentation**:
- Workflow questions: [TEAM_CONTACT_OR_DOCUMENTATION_LINK]
- Technical issues: [TECHNICAL_SUPPORT_CONTACT]
- Process improvements: [PROCESS_IMPROVEMENT_CONTACT]
