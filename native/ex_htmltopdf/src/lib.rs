//! Elixir NIF entry point for sghtmltopdf.
//!
//! This layer is kept thin, mirroring the upstream Ruby binding: the Elixir
//! side assembles the option argv, and this side passes it through the same
//! CLI parser used by the CLI and HTTP server, then renders. No option
//! semantics live here.

use std::io::Cursor;
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::path::PathBuf;
use std::sync::atomic::{AtomicU64, Ordering};

use rustler::{Binary, Encoder, Env, NewBinary, Term};
use sghtmltopdf_core::cli::{self, convert, CliError};
use sghtmltopdf_core::sink::{FileSink, MemorySink};

mod atoms {
    rustler::atoms! {
        ok,
        error,
        usage,
        input,
        render,
        timeout,
        panic,
    }
}

/// Renders `html` to a PDF returned as a binary.
///
/// The whole render runs on a dirty CPU scheduler; `with_render_stack` moves
/// it onto a dedicated 16 MiB-stack thread because layout/paint recursion can
/// exceed default thread stacks (upstream renders on such a thread from every
/// entry point).
#[rustler::nif(schedule = "DirtyCpu")]
fn render<'a>(env: Env<'a>, html: Binary<'a>, argv: Vec<String>) -> Term<'a> {
    let html = html.as_slice();

    let result = contain_panic(AssertUnwindSafe(|| {
        let (args, fonts) = cli::parse_convert_argv(&argv)?;
        cli::with_render_stack(|| {
            convert::render_to_memory(&args, &fonts, Cursor::new(html), MemorySink::new())
        })
    }));

    match result {
        Ok(pdf) => {
            let mut bin = NewBinary::new(env, pdf.len());
            bin.as_mut_slice().copy_from_slice(&pdf);
            (atoms::ok(), Binary::from(bin)).encode(env)
        }
        Err(err) => error_term(env, err),
    }
}

/// Renders `html` to a PDF written at `path`.
///
/// Writes are atomic: the render goes to a sibling temp path and is renamed
/// into place on success, so a failed render never leaves a truncated PDF
/// behind. [`FileSink`] already does temp+rename, but derives its temp name
/// from the process id alone — unique per CLI invocation, **not** unique when
/// N dirty schedulers render to the same path inside one BEAM process. We
/// point FileSink at a per-call unique intermediate (its own temp name derives
/// from that, staying unique too) and do the final rename ourselves. The
/// `--output -` the Elixir side puts in argv is a placeholder and is not used.
#[rustler::nif(schedule = "DirtyCpu")]
fn render_to_file<'a>(env: Env<'a>, html: Binary<'a>, argv: Vec<String>, path: String) -> Term<'a> {
    static CALL_SEQ: AtomicU64 = AtomicU64::new(0);

    let html = html.as_slice();

    let result = contain_panic(AssertUnwindSafe(|| {
        let (args, fonts) = cli::parse_convert_argv(&argv)?;
        let path = PathBuf::from(path);

        let mut intermediate = path.clone().into_os_string();
        intermediate.push(format!(
            ".{}-{}.part",
            std::process::id(),
            CALL_SEQ.fetch_add(1, Ordering::Relaxed)
        ));
        let intermediate = PathBuf::from(intermediate);

        let sink = FileSink::create(&intermediate)
            .map_err(|e| CliError::Input(format!("failed to create {}: {e}", path.display())))?;
        cli::with_render_stack(|| convert::render(&args, &fonts, Cursor::new(html), sink))?;

        std::fs::rename(&intermediate, &path).map_err(|e| {
            let _ = std::fs::remove_file(&intermediate);
            CliError::Input(format!("failed to move PDF into {}: {e}", path.display()))
        })
    }));

    match result {
        Ok(()) => atoms::ok().encode(env),
        Err(err) => error_term(env, err),
    }
}

/// Calls one real core symbol so tests can prove the NIF loaded and linked
/// against sghtmltopdf-core without paying for a render (same probe the Ruby
/// binding uses).
#[rustler::nif]
fn default_page_size() -> String {
    let settings = sghtmltopdf_core::layout::PageSettings::default();
    format!("{}x{}", settings.size.width, settings.size.height)
}

/// An error crossing back to the BEAM: either a structured [`CliError`] or a
/// caught panic message.
enum NifError {
    Cli(CliError),
    Panic(String),
}

impl From<CliError> for NifError {
    fn from(e: CliError) -> Self {
        Self::Cli(e)
    }
}

/// Runs `f`, converting any panic into a bounded error instead of letting it
/// unwind into the scheduler. Rustler would catch it too, but as an opaque
/// `ErlangError`; this keeps the `{:error, {kind, message}}` contract total.
fn contain_panic<R>(
    f: impl FnOnce() -> Result<R, CliError> + std::panic::UnwindSafe,
) -> Result<R, NifError> {
    match catch_unwind(f) {
        Ok(result) => result.map_err(NifError::Cli),
        Err(payload) => {
            let msg = if let Some(s) = payload.downcast_ref::<&str>() {
                (*s).to_string()
            } else if let Some(s) = payload.downcast_ref::<String>() {
                s.clone()
            } else {
                "unknown panic".to_string()
            };
            Err(NifError::Panic(format!("panic in sghtmltopdf: {msg}")))
        }
    }
}

/// `{:error, {kind, message}}` — kinds mirror `CliError`'s exit-code variants.
fn error_term(env: Env<'_>, err: NifError) -> Term<'_> {
    let (kind, message) = match err {
        NifError::Cli(CliError::Usage(m)) => (atoms::usage(), m),
        NifError::Cli(CliError::Input(m)) => (atoms::input(), m),
        NifError::Cli(CliError::Render(m)) => (atoms::render(), m),
        NifError::Cli(CliError::Timeout(m)) => (atoms::timeout(), m),
        NifError::Panic(m) => (atoms::panic(), m),
    };
    (atoms::error(), (kind, message)).encode(env)
}

rustler::init!("Elixir.ExHtmltopdf.Native");
