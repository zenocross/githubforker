#!/bin/bash

# GitHub Repository Forker using GitHub CLI
# Usage: ./github_forker.sh owner/repo [--branch main] [--copy-issues] [--target-name new-name]

set -e  # Exit on any error

# Default values
BRANCH=""
COPY_ISSUES=false
REPO=""
TARGET_NAME=""

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --branch)
            if [[ -z "$2" || "$2" == --* ]]; then
                echo "Error: --branch requires a branch name"
                exit 1
            fi
            BRANCH="$2"
            shift 2
            ;;
        --copy-issues)
            COPY_ISSUES=true
            shift
            ;;
        --target-name)
            if [[ -z "$2" || "$2" == --* ]]; then
                echo "Error: --target-name requires a repository name"
                exit 1
            fi
            TARGET_NAME="$2"
            shift 2
            ;;
        --help|-h)
            echo "Usage: $0 owner/repo [OPTIONS]"
            echo ""
            echo "OPTIONS:"
            echo "  --branch BRANCH       Set default branch for the forked repository"
            echo "  --copy-issues         Copy open issues from source repository"
            echo "  --target-name NAME    Custom name for the forked repository"
            echo "  --help, -h           Show this help message"
            echo ""
            echo "EXAMPLES:"
            echo "  $0 zenocross/puter"
            echo "  $0 zenocross/puter --branch main"
            echo "  $0 zenocross/puter --copy-issues"
            echo "  $0 zenocross/puter --target-name my-puter"
            echo "  $0 zenocross/puter --branch main --copy-issues --target-name my-custom-puter"
            exit 0
            ;;
        --*)
            echo "Error: Unknown option $1"
            echo "Use --help for usage information"
            exit 1
            ;;
        *)
            if [[ -z "$REPO" ]]; then
                REPO="$1"
            else
                echo "Error: Too many arguments. Repository '$REPO' already specified."
                echo "Unknown argument: $1"
                exit 1
            fi
            shift
            ;;
    esac
done

# Check if repository argument is provided
if [[ -z "$REPO" ]]; then
    echo "Error: Repository argument is required"
    echo "Usage: $0 owner/repo [OPTIONS]"
    echo "Use --help for more information"
    exit 1
fi

echo "GitHub Repository Forker"
echo "=" | tr -c '\n' '=' | head -c 50; echo
echo "Source repository: $REPO"
[[ -n "$TARGET_NAME" ]] && echo "Target name: $TARGET_NAME"
[[ -n "$BRANCH" ]] && echo "Default branch: $BRANCH"
[[ "$COPY_ISSUES" == true ]] && echo "Will copy issues: Yes" || echo "Will copy issues: No"
echo

# Check if GitHub CLI is installed
if ! command -v gh &> /dev/null; then
    echo "Error: GitHub CLI (gh) is not installed"
    echo ""
    echo "Install instructions:"
    echo "  Ubuntu/Debian: sudo apt install gh"
    echo "  macOS:         brew install gh"
    echo "  Other:         https://cli.github.com/"
    exit 1
fi

# Check if user is authenticated
echo "🔑 Step 1: GitHub Authentication Required"
echo "For security, please authenticate with GitHub CLI..."

# Force logout any existing session
gh auth logout --hostname github.com 2>/dev/null || true

echo "Please login with your GitHub account:"
if ! gh auth login --hostname github.com; then
    echo "Authentication failed"
    exit 1
fi

# Verify authentication worked
if ! gh auth status &> /dev/null; then
    echo "Authentication verification failed"
    exit 1
fi

# Get current user
CURRENT_USER=$(gh api user --jq '.login')
echo "✅ Authenticated as: $CURRENT_USER"

# Extract owner and repo name
IFS='/' read -r OWNER REPO_NAME <<< "$REPO"

# Validate repository format
if [[ -z "$OWNER" || -z "$REPO_NAME" ]]; then
    echo "Error: Invalid repository format. Use 'owner/repo-name'"
    exit 1
fi

# Check if trying to fork own repository
if [[ "$OWNER" == "$CURRENT_USER" ]]; then
    echo "Error: Cannot fork your own repository ($REPO)"
    echo "Please use a repository owned by a different user"
    exit 1
fi

# Use custom target name if provided, otherwise use original repo name
FORK_NAME="${TARGET_NAME:-$REPO_NAME}"
FORK_REPO="$CURRENT_USER/$FORK_NAME"

# Step 2: Fork the repository
echo ""
echo "Step 2: Setting up repository..."

# Check if target repository already exists
if gh repo view "$FORK_REPO" &> /dev/null; then
    echo "ℹ️  Repository already exists: $FORK_REPO"
    echo "✅ Using existing repository"
else
    echo "🔄 Forking repository..."
    
    # Fork the repository first
    if gh repo fork "$REPO" --clone=false > /dev/null 2>&1; then
        echo "✅ Fork created as $CURRENT_USER/$REPO_NAME"
        
        # If custom target name is specified and different from original, rename it
        if [[ -n "$TARGET_NAME" && "$TARGET_NAME" != "$REPO_NAME" ]]; then
            echo "🏷️  Renaming repository to $TARGET_NAME..."
            sleep 2  # Wait for fork to be ready
            
            if gh api "repos/$CURRENT_USER/$REPO_NAME" -X PATCH -f name="$TARGET_NAME" > /dev/null 2>&1; then
                echo "✅ Repository renamed to $FORK_REPO"
            else
                echo "⚠️  Warning: Could not rename repository to $TARGET_NAME"
                echo "    Repository remains as $CURRENT_USER/$REPO_NAME"
                FORK_REPO="$CURRENT_USER/$REPO_NAME"
                FORK_NAME="$REPO_NAME"
            fi
        else
            echo "✅ Fork ready at $FORK_REPO"
        fi
        
        # Wait a moment for changes to propagate
        sleep 2
    else
        echo "❌ Failed to fork repository"
        echo "This could be due to:"
        echo "  - Repository doesn't exist or is private"
        echo "  - You don't have permission to fork it"
        echo "  - Network connectivity issues"
        exit 1
    fi
fi

# Step 3: Set default branch if specified
if [[ -n "$BRANCH" ]]; then
    echo ""
    echo "Step 3: Setting default branch to $BRANCH..."
    
    # Check if branch exists in the fork
    if gh api "repos/$FORK_REPO/branches/$BRANCH" > /dev/null 2>&1; then
        if gh api "repos/$FORK_REPO" -X PATCH -f default_branch="$BRANCH" > /dev/null 2>&1; then
            echo "Default branch set to $BRANCH"
        else
            echo "Warning: Could not set default branch to $BRANCH"
        fi
    else
        echo "Warning: Branch '$BRANCH' does not exist in the fork"
        echo "Available branches:"
        gh api "repos/$FORK_REPO/branches" --jq '.[].name' 2>/dev/null | sed 's/^/  - /' || echo "  Could not fetch branches"
    fi
else 
    echo "Step 3: BRANCH not specified, using default branch..."
fi

# Step 4: Enable issues
echo ""
echo "📋 Step 4: Enabling issues..."
if gh api "repos/$FORK_REPO" -X PATCH -f has_issues=true > /dev/null 2>&1; then
    echo "✅ Issues enabled successfully"
else
    echo "⚠️  Warning: Could not enable issues"
fi

# This is the improved issue copying section to replace lines 181-284 in github_forker.sh
# Step 5: Copy issues if requested
if [[ "$COPY_ISSUES" == true ]]; then
    echo ""
    echo "📋 Step 5: Copying issues from source repository..."
    
    # Get all open issues from source repository (excluding pull requests)
    echo "🔍 Fetching issues from $REPO..."
    
    # Create a temporary file with unique name
    TEMP_ISSUES_FILE="/tmp/github_issues_${RANDOM}_$$.json"
    
    # Get the full JSON array of issues first
    if gh api "repos/$REPO/issues" --paginate --jq '[.[] | select(.pull_request == null and .state == "open")] | sort_by(.number)' > "$TEMP_ISSUES_FILE" 2>&1; then
        echo "✅ Successfully fetched issues"
    else
        echo "❌ Failed to fetch issues"
        rm -f "$TEMP_ISSUES_FILE"
        echo "⚠️  Continuing without copying issues..."
    fi
    
    # Check if we got valid JSON and count issues
    if [[ -f "$TEMP_ISSUES_FILE" ]] && ISSUE_COUNT=$(jq '. | length' "$TEMP_ISSUES_FILE" 2>/dev/null); then
        echo "✅ Found $ISSUE_COUNT open issues"
    else
        echo "❌ Failed to parse issues data"
        rm -f "$TEMP_ISSUES_FILE"
        echo "⚠️  Continuing without copying issues..."
    fi
    
    if [[ "$ISSUE_COUNT" -eq 0 ]]; then
        echo "ℹ️  No open issues found to copy"
        rm -f "$TEMP_ISSUES_FILE"
    else
        echo "📝 Copying $ISSUE_COUNT issues..."
        
        # Copy each issue
        COPIED_COUNT=0
        FAILED_COUNT=0
        
        for ((i=0; i<ISSUE_COUNT; i++)); do
            echo ""
            echo "📝 Processing issue $((i+1))/$ISSUE_COUNT..."
            
            # Extract issue data using jq with proper error handling
            if ! TITLE=$(jq -r ".[$i].title" "$TEMP_ISSUES_FILE" 2>/dev/null) || [[ "$TITLE" == "null" ]]; then
                echo "  ⚠️  Failed to extract title for issue $((i+1)), skipping..."
                ((FAILED_COUNT++))
                continue
            fi
            
            BODY=$(jq -r ".[$i].body // \"\"" "$TEMP_ISSUES_FILE" 2>/dev/null || echo "")
            ISSUE_NUMBER=$(jq -r ".[$i].number" "$TEMP_ISSUES_FILE" 2>/dev/null || echo "unknown")
            ORIGINAL_URL=$(jq -r ".[$i].html_url" "$TEMP_ISSUES_FILE" 2>/dev/null || echo "")
            
            echo "  Issue #$ISSUE_NUMBER: ${TITLE:0:50}..."
            
            # Prepare issue body with reference to original
            NEW_BODY="*Copied from [$REPO#$ISSUE_NUMBER]($ORIGINAL_URL)*

---

$BODY"
            
            # Get labels as a comma-separated string
            LABELS=$(jq -r ".[$i].labels[]?.name // empty" "$TEMP_ISSUES_FILE" 2>/dev/null | tr '\n' ',' | sed 's/,$//' || echo "")
            
            # Create labels first if they don't exist
            if [[ -n "$LABELS" ]]; then
                echo "  🏷️  Processing labels: $LABELS"
                IFS=',' read -ra LABEL_ARRAY <<< "$LABELS"
                for label in "${LABEL_ARRAY[@]}"; do
                    if [[ -n "$label" ]]; then
                        # Get label info from source repo and create in fork
                        if LABEL_INFO=$(gh api "repos/$REPO/labels/$label" 2>/dev/null); then
                            LABEL_COLOR=$(echo "$LABEL_INFO" | jq -r '.color // "d73a4a"' 2>/dev/null)
                            LABEL_DESC=$(echo "$LABEL_INFO" | jq -r '.description // ""' 2>/dev/null)
                            
                            # Create label in fork if it doesn't exist (suppress errors if already exists)
                            gh api "repos/$FORK_REPO/labels" -X POST \
                                -f name="$label" \
                                -f color="$LABEL_COLOR" \
                                -f description="$LABEL_DESC" &>/dev/null || true
                        fi
                    fi
                done
            fi
            
            # Create the issue
            echo "  📝 Creating issue..."
            
            CREATE_RESULT=""
            if [[ -n "$LABELS" ]]; then
                CREATE_RESULT=$(gh issue create --repo "$FORK_REPO" \
                    --title "$TITLE" \
                    --body "$NEW_BODY" \
                    --label "$LABELS" 2>&1)
                CREATE_EXIT_CODE=$?
            else
                CREATE_RESULT=$(gh issue create --repo "$FORK_REPO" \
                    --title "$TITLE" \
                    --body "$NEW_BODY" 2>&1)
                CREATE_EXIT_CODE=$?
            fi
            
            # Check if issue creation was successful
            if [[ $CREATE_EXIT_CODE -eq 0 && -n "$CREATE_RESULT" && "$CREATE_RESULT" == https://github.com/* ]]; then
                # Extract issue number from URL
                echo "DEBUG: CREATE_RESULT = '$CREATE_RESULT'"

                NEW_ISSUE_NUMBER=$(echo "$CREATE_RESULT" | grep -o '/issues/[0-9]*' | grep -o '[0-9]*' || echo "unknown")
                echo "  ✅ Created issue #$NEW_ISSUE_NUMBER"
                COPIED_COUNT=$((COPIED_COUNT + 1))
            else
                echo "  ⚠️  Warning: Could not copy issue #$ISSUE_NUMBER"
                if [[ -n "$CREATE_RESULT" ]]; then
                    echo "     Error: $CREATE_RESULT"
                fi
                FAILED_COUNT=$((FAILED_COUNT + 1))
            fi
            
            # Rate limiting protection
            sleep 1
        done
        
        # Clean up temp file
        rm -f "$TEMP_ISSUES_FILE"
        
        echo ""
        if [[ $COPIED_COUNT -gt 0 ]]; then
            echo "✅ Successfully copied $COPIED_COUNT out of $ISSUE_COUNT issues"
        fi
        
        if [[ $FAILED_COUNT -gt 0 ]]; then
            echo "⚠️  Failed to copy $FAILED_COUNT issues"
        fi
    fi
else
    echo ""
    echo "ℹ️  Step 5: Skipping issue copying (--copy-issues not specified)"
fi

# Final summary
echo ""
echo "🎉 All done!"
FORK_URL="https://github.com/$FORK_REPO"
echo "📁 Your repository: $FORK_URL"

if [[ "$COPY_ISSUES" == true ]]; then
    echo "🐛 Issues: $FORK_URL/issues"
fi

echo ""
echo "💡 Next steps:"
echo "  - Clone locally:  gh repo clone $FORK_REPO"
echo "  - View online:    $FORK_URL"
echo "  - Open in VS Code: gh repo clone $FORK_REPO && code $FORK_NAME"