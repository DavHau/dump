---
title: "Nix Ci on Github"
date: 2023-06-05T16:43:35+02:00
draft: false
---

This brain dump is split into two parts.

The first part is there to remind us of the [**goals**](#part-1-goals) we want to achieve with our CI-system.

The second part proposes some [**guidelines**](#part-2-guidelines) that support us in reaching these goals.

## Part 1: Goals

This is a list of goals that we want to achieve with our CI system.  

The goals are not ordered by priority or any other particular way.

If a change brings the system closer towards meeting the described goals, it's a good change.  

If a change moves the system away from these goals, it should be regarded with care. In this case it's a good idea to invest some time thinking about alternatives and discussing the solution with others before implementing it. It's much easier to change an idea before becoming invested in its implementation.

### (a) Fast CI jobs

We want our CI jobs to be as fast as possible, to reduce the time PR authors need to wait until getting a green or red signal.

The underlying reason is that slow CI generates context switching and slows down the team. Ideally we want the CI to finish in 1 minute for the hot path.

### (b) Portable CI jobs

We want to make it easy to execute the jobs anywhere.

The jobs should not be tied to github or any other specific cloud environment.

Developers should be able to just simply execute any job they want on their local machine.

The underlying reason is that it's generally faster for developers to debug things locally.

### (c) Reproducible CI jobs

If a job fails in the CI pipeline, it should also fail when executed on the developers machine.

If a job succeeds on a developers machine, it should also succeed in the CI pipeline.

There should not be the necessity to push code to a PR and wait for a workflow to trigger in order to validate ones code.

### (d) Simple debugging of CI jobs

If a job in the CI pipeline fails, it should be obvious to an observer how to reproduce the failure locally.

It should, for example, be simple to understand which CI code is responsible for the failed Job and which is not.

### (e) Simple contributing / onboarding

The CI related code should be structured and documented in a way that makes it simple for previously unfamiliar developers to become productive on it as quickly as possible. It is undesired to have a system which is understood by a single person or team while being a blackbox for others.

The optimal DevOps scenario is when there is no separate ownership of the CI code to a specific person or team. Instead developers themselves take part in maintaining the parts of the CI pipeline relevant to their concerns.

## Part 2: Guidelines

### 1. No shell code in github yml files

Jobs defined in .yml files should not contain any shell code other than a single line that executes one command.

Contributes to goals:

- (b) Portable CI jobs
- (c) Reproducible CI jobs
- (d) Simple debugging of CI jobs

(b) Shell code embedded in github .yml files is not portable to other environments or the local machine. The surrounding yaml introduces additional logic, which the shell becomes dependant on. This extra logic is specific to the single cloud provider github. It is not meant to be executed in other environments.

(c) Shell code embedded in github .yml files is not reproducible. There is no trivial way to reproduce the environment the script is executed in. The script becomes tied to the specific environment that the cloud CI system offers, for example, github's custom ubuntu distribution.

(d) Shell code embedded in github .yml files is hard to debug, as there is no quick feedback loop to test changes. To test a change, one must push the change to github and wait for the job to run. Depending on the size of the workflow this can be a matter of several minutes which is far from optimal. Little changes that could be made within minutes on a local script, quickly become a task of several hours.

The only shell code that should exist inside .yml files is single command executions to call a script or a program that is located somewhere else. These programs should be self contained and should offer good reproducibility. For example, the executed program could be a shell script with a hardcoded PATH or a nix derivation which is executed in the nix sandbox.

A point could be made for shell code with the sole purpose of interacting with github's environment itself. That code is not portable by definition, therefore factoring it out doesn't make it more portable.\
Though, even then, keeping shell code in .sh files is beneficial, because this allows to run static analysis, like shellcheck, etc.

### 2. Small work units

Larger units of work should be broken up into smaller sized, independent units.

Contributes to goals:

- (a) Fast CI jobs
- (d) Simple debugging of CI jobs
- (e) Simple contributing / onboarding

(a) Small units of work potentially make the CI run faster, because work units can be parallelized.

(b) Small units of work make it simpler to debug a failure. Small units allow to narrow down a problem to a smaller amount of code that is responsible for it. It's much simpler to debug a .yml consisting of 60 lines of code, compared to a yml. consisting of 600 lines of code.

(c) Small units of work make it simpler to onboard new contributors. If code is organized in large chunks, it requires investing mental capacity to understand what units it actually contains and how those are related to each other. Especially for new contributors it is better to find these units already separated from the start.

Heads UP:

- While the DRY pattern is generally a good idea, it can often get in the way of decoupling things into smaller units. Sometimes duplication is necessary in order to decouple things and that's OK.
- Smaller units might increase the total number of code lines in the CI, as previously shared code might need to be duplicated.
- There is a cost of initializing workflow runs, which in summary is increased by introducing more workflows, for example the time to install nix on github hosted runners etc.
- While this change can improve performance, it doesn't necessarily have to. Reducing the mental capacity for maintenance can often be worth more then a few seconds of runtime.
- Be careful with dependencies between work units. Often work units depend on each other and must run in a certain order. In this case, splitting them apart might not make sense.

### 3. Wrap all jobs with `nix run` or `nix build`

All CI jobs should be wrapped by `nix run` or `nix build`. This makes it simple to reproduce them locally and execute them in the CI pipeline without any extra glue code.

Programs executed via `nix run` should at least be wrapped with a static `PATH`, for example by using `writers.writeBash`.

Example:
```nix
pkgs.writers.writeBash "my-ci-job" {
  makeWrapperArgs = ["--set" "PATH" "${lib.makeBinPath [
    pkgs.hello
  ]}"]
} ''
echo my-ci-job
hello
''
```

This ensures reasonable reproducibility and allows developers to reproduce failures seen in the CI pipeline locally with ease.

A typical example of where this matters is the BSD utilities on macOS that don't take the same command-line flags as the GNU coreutils.

Contributes to Goals:

- (b) Portable CI jobs
- (c) Reproducible CI jobs
- (d) Simple debugging of CI jobs

### 4. CI logic inside current version of code

Checking out one revision of the repository should not only deliver the project code but also exactly the right version of CI code that is needed to verify the project.

The CI code should not be spread across different repositories or different revisions of a single repo.

Under normal circumstances the branch to verify should not be a parameter of the CI code. The CI code should always verify exactly the version that's represented by the current revision of the repository.

Contributes to Goals:

- (c) Reproducible CI jobs
- (d) Simple debugging of CI jobs

(c) It makes it hard to reproduce CI pipeline results if a combination of different repositories or a combinations of different revisions is needed to verify the project.

(d) It becomes harder to debug problems if the state that's needed to reproduce them is a mix of different repositories or revisions.

### 5. No inputs for CI jobs

The CI jobs should not take any user input except for debugging scenarios.

Contributes to Goals:

- (c) Reproducible CI jobs
- (d) Simple debugging of CI jobs

(c) It makes it hard to reproduce CI jobs if they take user input, because the input is not persisted in the code.

(d) It is hard to debug a CI job that takes user input because of the reproducibility problem.

Everything that is needed to verify a single version of the project should be contained within that single version of the project. If the CI logic requires configuration or arguments, those should be manifested inside the code of the same version of the repository.

For debugging purposes inputs could be used but requiring them should not be the default.

### 6. Document the code well

The CI code should be documented sufficiently well. For every snippet of code the should be a comment on what it does and why it's needed.

Contributes to Goals:

- (d) Simple debugging of CI jobs
- (e) Simple contributing / onboarding
