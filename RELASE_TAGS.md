Yes, you can easily tag a release through your GitHub Actions workflow by using GitHub's native REST API or specialized actions like [softprops/action-gh-release](https://github.com/marketplace/actions/create-tag-release). [1, 2, 3]
When you create an official "GitHub Release," GitHub automatically generates the underlying Git tag pointing to your current commit if it does not already exist. [4]

## Combined Workflow Example

You can expand your existing workflow_dispatch script to take a tag input, verify it, and then instantly create a formalized GitHub Release.

name: Manual Create Release Tag
on:
workflow_dispatch:
inputs:
tag_version:
description: 'Enter the tag version (e.g., v1.0.0)'
required: true
type: string
release_title:
description: 'Enter the Release Title'
required: false
type: string
jobs:
create-release:
runs-on: ubuntu-latest
permissions:
contents: write # Crucial: Allows the workflow to push tags and create releases
steps: - name: Checkout Code
uses: actions/checkout@v4

      - name: Build and Create Release
        uses: softprops/action-gh-release@v2
        with:
          tag_name: ${{ inputs.tag_version }}
          name: ${{ inputs.release_title || inputs.tag_version }}
          body: |
            Manual release generated via GitHub Actions workflow dispatch.          draft: false
          prerelease: false

## 3 Rules for Success

1.  Enable Write Permissions: By default, GitHub Action tokens may have read-only access. You must explicitly include permissions: contents: write in your job parameters, or the action will fail with a 403 Forbidden error. [5, 6]
2.  Automate Release Notes: If you don't want to type out a description manually, you can add generate_release_notes: true inside the with: block. GitHub will automatically compile a list of all pull requests and contributors since your previous tag. [4, 7]
3.  Trigger Secondary Workflows: If you have separate testing pipelines that trigger on tags: ['v*'], creating a release using the default ${{ secrets.GITHUB_TOKEN }} will not trigger them. To chain workflows, you must generate a [GitHub Personal Access Token (PAT)](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens) and pass it into the action using token: ${{ secrets.YOUR_CUSTOM_PAT }}. [1, 8]

# Tarballs
To install an Elixir package directly from a GitHub repository inside your GitHub Actions workflow, you do not even need to manually build or manage tarballs. Elixir’s build tool (mix) natively supports fetching specific branches, tags, or commits directly from GitHub.
## 1. Update your mix.exs File
Instead of using a traditional version number, point your dependency directly to the GitHub repository.

defp deps do
  [
    {:my_package, github: "username/repo-name", tag: "v1.0.0"}
    # Or use a specific branch: branch: "main"
    # Or use a specific commit hash: ref: "abcdef1"
  ]
end

## 2. GitHub Actions Workflow Configuration
When using private repositories, your GitHub Actions runner needs permission to clone the dependent repository. Use a GitHub Personal Access Token (PAT) or an SSH Deploy Key passed to the checkout step. [1, 2, 3] 
Here is a standard, optimized workflow for Elixir:

name: Elixir CI
on:
  push:
    branches: [ "main" ]
  pull_request:
    branches: [ "main" ]
jobs:
  build:
    name: Build and Test
    runs-on: ubuntu-latest

    steps:
    - name: Checkout Code
      uses: actions/checkout@v4
      with:
        # Pass a token if 'my_package' is in a private repo
        token: ${{ secrets.DEPENDENCY_GITHUB_TOKEN }} 

    - name: Set up Elixir
      uses: erlef/setup-beam@v1
      with:
        elixir-version: '1.16.0' # Specify your Elixir version
        otp-version: '26.0'      # Specify your OTP version

    - name: Retrieve Dependencies Cache
      uses: actions/cache@v4
      with:
        path: deps
        key: ${{ runner.os }}-mix-${{ hashFiles('**/mix.lock') }}
        restore-keys: |
          ${{ runner.os }}-mix-
    - name: Install Dependencies
      run: mix deps.get

    - name: Run Tests
      run: mix test

## Key Workflow Optimizations

* Erlef Setup: The erlef/setup-beam action is the official community standard for installing Elixir.
* Dependency Caching: The actions/cache step skips downloading your GitHub-based packages on every run unless mix.lock changes.
* Token Access: Store your GitHub PAT in your repository settings under Secrets and variables > Actions. [4, 5, 6, 7] 

Are your GitHub repositories public or private, and do you need help generating the correct GitHub token for access?

[1] [https://github.com](https://github.com/marketplace/actions/go-dependency-submission)
[2] [https://www.youtube.com](https://www.youtube.com/watch?v=6Ipi9tguYWw)
[3] [https://medium.com](https://medium.com/prompt/trigger-another-github-workflow-without-using-a-personal-access-token-f594c21373ef)
[4] [https://www.linkedin.com](https://www.linkedin.com/posts/prerana-moon-a7b8a925b_github-actions-real-time-interview-question-activity-7246895663999827969-eAmA)
[5] [https://www.tembo.io](https://www.tembo.io/blog/cross-repo-automation)
[6] [https://docs.gruntwork.io](https://docs.gruntwork.io/infrastructure-pipelines/hello-world/)
[7] [https://stackoverflow.com](https://stackoverflow.com/questions/68682406/stuck-at-using-pat-personal-access-token-in-github-actions)
