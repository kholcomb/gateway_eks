# Contributing to Gateway EKS

## Git Workflow (Git Flow)

We use a **Git Flow** branching model:

```
feature/my-feature → dev → main
```

- **`main`**: Production-ready code
- **`dev`**: Integration branch for features (default branch)
- **`feature/*`**: New features and enhancements

### Branch Protection Rules

- **main**: Protected, only `dev` can merge via PR
- **dev**: Protected, requires PR approval
- **feature branches**: Auto-deleted after merge

## Starting New Work

Always start from `dev`:

```bash
# Update dev branch
git checkout dev
git pull origin dev

# Create feature branch
git checkout -b feature/my-feature-name
```

### Branch Naming Conventions

- `feature/` - New features (e.g., `feature/redis-tls`)
- `fix/` - Bug fixes (e.g., `fix/authentication-timeout`)
- `chore/` - Maintenance tasks (e.g., `chore/update-dependencies`)
- `docs/` - Documentation updates (e.g., `docs/api-guide`)

## Making Changes

```bash
# Make your changes
vim file.txt

# Commit with conventional commits
git add file.txt
git commit -m "feat: add new feature"

# Push to remote
git push origin feature/my-feature-name
```

### Commit Message Format

We use [Conventional Commits](https://www.conventionalcommits.org/):

```
<type>: <description>

[optional body]

[optional footer]
```

**Types:**
- `feat`: New feature
- `fix`: Bug fix
- `chore`: Maintenance
- `docs`: Documentation
- `refactor`: Code refactoring
- `test`: Tests
- `ci`: CI/CD changes

**Examples:**
```bash
git commit -m "feat: add Redis TLS support"
git commit -m "fix: resolve JWT token expiration issue"
git commit -m "docs: update deployment instructions"
```

## Creating Pull Requests

### For Features (to dev)

```bash
# Create PR targeting dev (default)
gh pr create --base dev --title "Add my feature" --body "Description of changes"

# Or use the GitHub UI
```

**PR Requirements:**
- Target: `dev` branch
- 1 approval required
- All checks must pass
- Descriptive title and description
- Link to GitHub Issue (e.g., "Closes #45")

### For Releases (dev to main)

Only maintainers create these:

```bash
gh pr create --base main --head dev --title "Release: $(date +%Y-%m-%d)"
```

## After PR is Merged

GitHub automatically deletes the remote branch. Clean up locally:

```bash
# Switch back to dev
git checkout dev
git pull origin dev

# Delete local feature branch
git branch -d feature/my-feature-name
```

## Keeping Your Branches Clean

We've set up Git aliases to help:

### Show Branches Gone on Remote

```bash
git gone
```

### Clean Up Gone Branches

```bash
git cleanup-gone
```

### Sync Everything

```bash
git sync
```

## Regular Maintenance

Run weekly or after merging PRs:

```bash
# Update all branches and show status
git sync

# Clean up deleted branches
git cleanup-gone
```

## Common Tasks

### Update Your Feature Branch with Latest Dev

```bash
# While on your feature branch
git checkout feature/my-feature
git fetch origin
git rebase origin/dev
```

### Fix Merge Conflicts

```bash
# During rebase
# 1. Fix conflicts in files
vim conflicted_file.txt

# 2. Mark as resolved
git add conflicted_file.txt

# 3. Continue rebase
git rebase --continue
```

### Undo Last Commit (Not Pushed)

```bash
git reset --soft HEAD~1
```

### Amend Last Commit

```bash
git commit --amend -m "Updated commit message"
```

## Code Review Process

1. **Create PR** targeting `dev`
2. **Wait for CI** checks to pass
3. **Request review** from maintainers
4. **Address feedback** with new commits
5. **Approval** - Maintainer approves
6. **Merge** - Squash and merge to `dev`
7. **Clean up** - GitHub auto-deletes branch

## Release Process

1. Features accumulate in `dev`
2. When ready for release, create PR: `dev` → `main`
3. Final review and testing
4. Merge to `main`
5. Tag release: `git tag -a v1.0.0 -m "Release 1.0.0"`

## Getting Help

- **Questions**: Open a GitHub Discussion
- **Bugs**: Create an issue with `bug` label
- **Features**: Create an issue with `enhancement` label

## Additional Resources

- [Git Flow Cheatsheet](https://danielkummer.github.io/git-flow-cheatsheet/)
- [Conventional Commits](https://www.conventionalcommits.org/)
- [GitHub Flow](https://docs.github.com/en/get-started/using-github/github-flow)
