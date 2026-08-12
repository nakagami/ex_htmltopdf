# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Initial release: `ExSghtmltopdf.render/2`, `render!/2`, `render_to_file/3`,
  `render_to_file!/3` — HTML to PDF via a Rustler NIF over
  [sghtmltopdf](https://github.com/waka/sghtmltopdf) (pinned at v0.1.1,
  `d774b79a`), rendered on a dirty CPU scheduler with the engine's dedicated
  16 MiB render stack.
- `ExSghtmltopdf.Options` — keyword options mapped to the upstream CLI's
  shared option parser (one option surface across CLI/server/Ruby/Elixir).
- `ExSghtmltopdf.Error` with kinds `:usage`/`:input`/`:render`/`:timeout`
  mirroring the CLI error classes, and `:panic` for contained native panics.
- Precompiled NIFs for aarch64/x86_64 macOS and Linux via
  `rustler_precompiled`; `EXSGHTMLTOPDF_BUILD=1` forces a source build.
