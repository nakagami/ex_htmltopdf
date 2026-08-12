defmodule ExSghtmltopdf.Native do
  @moduledoc false

  # RustlerPrecompiled downloads a prebuilt NIF for the user's target from the
  # matching GitHub release. Local development / CI forces a from-source build
  # with EXSGHTMLTOPDF_BUILD=1 (see README "Development").
  #
  # IMPORTANT release ordering (learned the hard way on ExMonty): the precompiled
  # download is verified against `checksum-Elixir.ExSghtmltopdf.Native.exs`. That
  # file is regenerated AFTER the release workflow uploads the NIF artifacts, via
  #   mix rustler_precompiled.download ExSghtmltopdf.Native --all --print
  # and must exist before `mix hex.publish`. The release workflow does this
  # automatically. See UPDATE_PROCEDURE.md.

  @version Mix.Project.config()[:version]

  use RustlerPrecompiled,
    otp_app: :ex_sghtmltopdf,
    crate: "ex_sghtmltopdf",
    base_url: "https://github.com/jtippett/ex_sghtmltopdf/releases/download/v#{@version}",
    version: @version,
    targets: ~w(
      aarch64-apple-darwin
      x86_64-apple-darwin
      x86_64-unknown-linux-gnu
      aarch64-unknown-linux-gnu
    ),
    force_build: System.get_env("EXSGHTMLTOPDF_BUILD") in ["1", "true"]

  # Keep these stubs in sync with the #[rustler::nif] fns in
  # native/ex_sghtmltopdf/src/lib.rs. Each raises until the NIF library loads.

  def render(_html, _argv), do: :erlang.nif_error(:nif_not_loaded)
  def render_to_file(_html, _argv, _path), do: :erlang.nif_error(:nif_not_loaded)
  def default_page_size, do: :erlang.nif_error(:nif_not_loaded)
end
