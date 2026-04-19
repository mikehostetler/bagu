# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

<!-- changelog -->

## [v2.1.1](https://github.com/agentjido/jido_signal/compare/v2.1.0...v2.1.1) (2026-03-28)




### Bug Fixes:

* remove dead extension policy fallback (#130) by mikehostetler

## [v2.1.0](https://github.com/agentjido/jido_signal/compare/v2.0.0...v2.1.0) (2026-03-28)




### Features:

* add typed signal extension policy (#126) by mikehostetler

* add typed signal extension policy by mikehostetler

* dispatch: implement bus dispatch adapter (#117) by mikehostetler

* dispatch: implement bus dispatch adapter by mikehostetler

### Bug Fixes:

* remove invalid doctest-style doc examples (#127) by mikehostetler

* validate typed policy extension data by mikehostetler

* dispatch: align adapter type and examples with bus support by mikehostetler

## [2.0.0] - 2026-02-22

### Changed
- Promote the 2.0.0 release candidate line to stable 2.0.0
- Require Elixir `~> 1.18` and document OTP `27+` prerequisites
- Refresh package metadata/docs for the final 2.0 release

### Fixed
- Tighten bus persistence cleanup guard handling in `Bus.Subscriber`
- Remove stale commented skipped-test block from persistence coverage tests

## [v2.0.0-rc.5](https://github.com/agentjido/jido_signal/compare/v2.0.0-rc.4...v2.0.0-rc.5) (2026-02-16)




### Bug Fixes:

* format bus_subscriber conditional by mikehostetler

* relocate changelog marker for correct git_ops insertion by mikehostetler

* bus: async publish handling to avoid call-path blocking (#114) by mikehostetler

* bus: batch persistent fanout calls during publish (#115) by mikehostetler

* bus: batch persistent fanout calls during publish (#115) by mikehostetler

* bus: async publish handling to avoid call-path blocking (#114) by mikehostetler

* bus: validate persistent ack identifiers (#110) by mikehostetler

* ci: align bus_subscriber formatting with CI toolchain by mikehostetler

* bus: make dlq redrive non-blocking (#98) by mikehostetler

* ext: drain pending extension registrations on startup (#97) by mikehostetler

* ets: remove dynamic atom table naming (#96) by mikehostetler

* bus: resolve partition targets by name at runtime (#95) by mikehostetler

* bus: harden API calls against process races (#94) by mikehostetler

* middleware: isolate callback failures from callers (#93) by mikehostetler

* bus: remove replay dependence on :sys.get_state (#92) by mikehostetler

* bus: clean up owned resources on terminate (#90) by mikehostetler

* bus: fail fast on linked runtime child exits (#89) by mikehostetler

* bus: harden persistent subscription lifecycle (#91) by mikehostetler

* bus: harden persistent subscription lifecycle by mikehostetler

* signal: generate valid ids in map_to_signal_data (#88) by mikehostetler

* bus: order replay by recorded log keys (#87) by mikehostetler

* bus: harden :DOWN handling against stale subscriber state (#86) by mikehostetler

* bus: ignore stray down messages safely by mikehostetler

* stream: read correlation_id from extension metadata (#85) by mikehostetler

* bus: use millisecond checkpoints in reconnect replay (#84) by mikehostetler

* bus: propagate persistent ack errors to callers (#83) by mikehostetler

* bus: propagate persistent ack errors by mikehostetler

* bus: enforce unsubscribe delete_persistence semantics (#82) by mikehostetler

* bus: enforce delete_persistence unsubscribe semantics by mikehostetler

* bus: support persistent option alias in subscribe (#81) by mikehostetler

* dispatch: instance-scoped task supervisor selection (#80) by mikehostetler

* dispatch: support instance-scoped task supervisors by mikehostetler

* bus: scope partition registry by instance (#79) by mikehostetler

### Refactoring:

* bus: share dispatch middleware flow across Bus and Partition (#116) by mikehostetler

* bus: extract shared dispatch middleware flow by mikehostetler

* bus: extract shared dispatch middleware flow by mikehostetler

## [2.0.0-rc.4] - 2026-02-06

### Changed
- Removed quokka from dev dependencies (#74)
- Removed unused {:private} dependency (#75)

## [2.0.0-rc.3] - 2026-02-04

### Fixed
- Elixir 1.18 compatibility (#73)

### Changed
- Bump zoi from 0.16.1 to 0.17.0
- Bump credo from 1.7.15 to 1.7.16
- Bump ex_doc from 0.40.0 to 0.40.1

## [2.0.0-rc.2] - 2025-01-30

### Added
- Instance isolation support for multi-tenant deployments via `jido:` option

### Changed
- **BREAKING:** Removed `typed_struct` dependency - all structs now use Zoi-based definitions
- Refactored helpers extraction and improved code organization
- Hardened ETS cleanup in tests

### Fixed
- TrieNode.handlers default in Router

## [1.1.0] - 2025-06-18

### Added
- Parallel dispatch processing for multiple targets with configurable concurrency (default: 8)
- Configuration option `:dispatch_max_concurrency` to control parallel dispatch concurrency
- Self-call detection for Named adapter in sync mode to prevent deadlocks
- Payload size limits and schema validation for Signal serialization

### Changed
- **BREAKING:** `dispatch/2` with multiple configs now returns `{:error, [errors]}` instead of first error only
- Removed double validation overhead (internal optimization - no API impact)
- Simplified batch processing to use single async stream (internal optimization)
- Improved batch dispatch concurrency defaults from 5 to 8
- Deprecated `jido_dispatch` field in Signal struct

### Deprecated
- `batch_size` option in `dispatch_batch/3` - kept for backwards compatibility but no longer used

### Performance
- ~40% reduction in hot-path overhead from eliminating double validation
- Significant speedup for multi-target dispatch (e.g., 10 targets with 100ms latency: ~200ms vs ~1000ms sequential)
- **Router optimizations (50-100x improvement in pattern matching):**
  - Optimized `Router.matches?/2` - eliminated trie build and UUID generation per call
  - Optimized multi-wildcard (`**`) matching - reduced memory allocations
  - Optimized `route_count` tracking - O(N) → O(1) for removal operations
  - Optimized `has_route?/2` - O(N) → O(depth) direct trie lookup
  - Optimized trie build - precomputed segments to avoid repeated string splits

### Fixed
- Named adapter now prevents self-call deadlocks in sync delivery mode
- Documentation examples and bugs (Fixes #11, #12, Refs #13)
- Flaky DispatchTest by isolating tests that modify global Application env

## [1.0.0] - 2025-02-03

### Added
- Initial release of Jido Signal
- Signal processing and event handling framework
- Bus-based pub/sub system with adapters
- Signal routing with pattern matching
- Multiple dispatch adapters: `:pid`, `:pubsub`, `:http`, `:bus`, `:named`, `:console`, `:logger`, `:noop`
- In-memory persistence via ETS
- Middleware pipeline support
- Comprehensive test suite with 80%+ coverage
- Documentation with guides and examples
- OTP supervision tree architecture

[Unreleased]: https://github.com/agentjido/jido_signal/compare/v2.0.0...HEAD
[2.0.0]: https://github.com/agentjido/jido_signal/compare/v2.0.0-rc.5...v2.0.0
[2.0.0-rc.4]: https://github.com/agentjido/jido_signal/compare/v2.0.0-rc.3...v2.0.0-rc.4
[2.0.0-rc.3]: https://github.com/agentjido/jido_signal/compare/v2.0.0-rc.2...v2.0.0-rc.3
[2.0.0-rc.2]: https://github.com/agentjido/jido_signal/compare/v1.1.0...v2.0.0-rc.2
[1.1.0]: https://github.com/agentjido/jido_signal/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/agentjido/jido_signal/releases/tag/v1.0.0
