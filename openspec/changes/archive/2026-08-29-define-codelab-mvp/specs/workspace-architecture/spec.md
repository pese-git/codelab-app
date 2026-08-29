## ADDED Requirements

### Requirement: Monorepo package boundaries
CodeLab SHALL use a Dart/Flutter/FVM/Melos monorepo with separated packages for `acp_protocol`, `acp_transports`, `acp_client_core`, `acp_testing`, `acp_ui`, and `codelab_app`.

#### Scenario: Workspace packages are present
- **WHEN** implementation bootstraps the workspace
- **THEN** the repository contains the required packages and each package has its own `pubspec.yaml`

#### Scenario: Pure Dart packages stay Flutter-free
- **WHEN** static analysis runs for `packages/dart/*`
- **THEN** no pure Dart package imports Flutter, `fluent_ui`, Bloc, or app UI code

### Requirement: Clean Architecture boundaries
CodeLab SHALL follow Clean Architecture with hexagonal boundaries where `Domain` and `Application` do not depend on `Presentation` or concrete `Infrastructure`.

#### Scenario: Domain depends only on abstractions
- **WHEN** a use case needs transport, logging, approval, or persistence behavior
- **THEN** it depends on a port/interface rather than a concrete adapter

#### Scenario: Infrastructure is wired at composition root
- **WHEN** the app starts
- **THEN** concrete adapters are connected in `apps/codelab_app` composition root

### Requirement: SOLID, KISS, and DRY constraints
CodeLab SHALL enforce SOLID, KISS, and DRY as implementation constraints without creating premature abstractions or god services.

#### Scenario: Service responsibility remains narrow
- **WHEN** a service is added
- **THEN** it has one clear responsibility and does not combine protocol, transport, state, approvals, and UI side effects

#### Scenario: Shared logic is centralized
- **WHEN** ACP codecs, state transitions, or reusable UI primitives are implemented
- **THEN** they are centralized in `acp_protocol`, `acp_client_core`, or `acp_ui/atomics` respectively

### Requirement: CherryPick dependency injection
CodeLab SHALL use CherryPick v4.x.x as the DI framework, configured at the app composition root.

#### Scenario: Root scope lifecycle
- **WHEN** the Flutter app boots and shuts down
- **THEN** CherryPick root scope is created during bootstrap and closed during shutdown

#### Scenario: Domain avoids service locator access
- **WHEN** a domain or application class needs dependencies
- **THEN** it receives them through constructors or factories, not arbitrary service locator lookup

### Requirement: Standard modeling libraries
CodeLab SHALL use `fpdart` for typed recoverable results/options and `freezed` for immutable state, DTOs, and union models where they improve type safety.

#### Scenario: Recoverable failure is modeled
- **WHEN** a use case can fail without crashing the app
- **THEN** it returns a typed result such as `Either` rather than throwing unstructured exceptions

#### Scenario: Union state is modeled
- **WHEN** session, prompt turn, or approval state has multiple variants
- **THEN** it is represented with immutable typed models suitable for exhaustive handling
