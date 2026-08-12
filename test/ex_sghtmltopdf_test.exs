defmodule ExSghtmltopdfTest do
  use ExUnit.Case, async: true

  alias ExSghtmltopdf.Error

  doctest ExSghtmltopdf

  @html "<!doctype html><html><body><h1>Hello, PDF</h1><p>from Elixir</p></body></html>"

  describe "NIF loading" do
    test "the native library links against sghtmltopdf-core" do
      assert ExSghtmltopdf.Native.default_page_size() =~ ~r/^\d+(\.\d+)?x\d+(\.\d+)?$/
    end

    test "upstream_revision/0 exposes the Cargo pin" do
      assert ExSghtmltopdf.upstream_revision() =~ ~r/^[0-9a-f]{40}$/
    end
  end

  describe "render/2" do
    test "renders HTML to a PDF binary" do
      assert {:ok, pdf} = ExSghtmltopdf.render(@html)
      assert <<"%PDF-", _::binary>> = pdf
    end

    test "accepts iodata" do
      assert {:ok, <<"%PDF-", _::binary>>} =
               ExSghtmltopdf.render(["<h1>", "chunked", "</h1>"])
    end

    test "options actually reach the engine (A5 changes the MediaBox)" do
      {:ok, a4} = ExSghtmltopdf.render(@html, page_size: "A4", grayscale: true)
      {:ok, a5} = ExSghtmltopdf.render(@html, page_size: "A5", grayscale: true)

      assert a4 =~ "MediaBox [0 0 595.275 841.875]"
      assert a5 =~ "MediaBox [0 0 419.55002 595.275]"
    end

    test "empty HTML still renders a document" do
      assert {:ok, <<"%PDF-", _::binary>>} = ExSghtmltopdf.render("")
    end

    test "an unknown option is a :usage error, not a crash" do
      assert {:error, %Error{kind: :usage, message: message}} =
               ExSghtmltopdf.render(@html, no_such_option: "x")

      assert message =~ "no-such-option"
    end

    test "an unsupported wkhtmltopdf option is a :usage error" do
      # upstream keeps a deliberate unsupported-flags list with explanations
      assert {:error, %Error{kind: :usage}} =
               ExSghtmltopdf.render(@html, enable_javascript: true)
    end

    test "a missing font file is an :input error" do
      assert {:error, %Error{kind: :input}} =
               ExSghtmltopdf.render(@html, font: "/nonexistent/font.ttf")
    end

    test "an engine constraint is a :render error ([topage] in streaming mode)" do
      assert {:error, %Error{kind: :render}} =
               ExSghtmltopdf.render(@html,
                 streaming: true,
                 footer_center: "Page [page] of [topage]"
               )
    end

    test "the VM and session survive an error (subsequent renders work)" do
      assert {:error, _} = ExSghtmltopdf.render(@html, font: "/nonexistent/font.ttf")
      assert {:ok, _} = ExSghtmltopdf.render(@html)
    end
  end

  describe "render!/2" do
    test "returns the PDF binary" do
      assert <<"%PDF-", _::binary>> = ExSghtmltopdf.render!(@html)
    end

    test "raises ExSghtmltopdf.Error with the kind in the message" do
      assert_raise Error, ~r/\(usage\)/, fn ->
        ExSghtmltopdf.render!(@html, bogus: "yes")
      end
    end
  end

  describe "render_to_file/3" do
    @tag :tmp_dir
    test "writes a PDF to the given path", %{tmp_dir: tmp} do
      path = Path.join(tmp, "out.pdf")
      assert :ok = ExSghtmltopdf.render_to_file(@html, path)
      assert <<"%PDF-", _::binary>> = File.read!(path)
    end

    @tag :tmp_dir
    test "a failed parse never creates a file", %{tmp_dir: tmp} do
      path = Path.join(tmp, "never.pdf")

      assert {:error, %Error{kind: :usage}} =
               ExSghtmltopdf.render_to_file(@html, path, bogus: true)

      assert File.ls!(tmp) == []
    end

    @tag :tmp_dir
    test "a render failing mid-write leaves neither the PDF nor a temp file", %{tmp_dir: tmp} do
      path = Path.join(tmp, "never.pdf")

      # header_html is only read inside the render, after the sink is created —
      # this exercises the temp-file cleanup path, not just the parse guard.
      assert {:error, %Error{kind: :input}} =
               ExSghtmltopdf.render_to_file(@html, path, header_html: "/definitely/missing.html")

      assert File.ls!(tmp) == []
    end

    @tag :tmp_dir
    test "concurrent writes to the same path are atomic (no interleaved temp files)",
         %{tmp_dir: tmp} do
      path = Path.join(tmp, "same.pdf")

      1..8
      |> Task.async_stream(
        fn i -> :ok = ExSghtmltopdf.render_to_file("<h1>writer #{i}</h1>", path) end,
        timeout: 60_000
      )
      |> Stream.run()

      # Exactly the final PDF remains — no .part/.tmp leftovers — and it is
      # one writer's intact output, not an interleaving.
      assert File.ls!(tmp) == ["same.pdf"]
      assert <<"%PDF-", _::binary>> = File.read!(path)
    end

    test "an unwritable output path is an :input error" do
      assert {:error, %Error{kind: :input}} =
               ExSghtmltopdf.render_to_file(@html, "/nonexistent-dir/out.pdf")
    end
  end

  describe "concurrency" do
    test "parallel renders are independent" do
      results =
        1..4
        |> Task.async_stream(fn i -> ExSghtmltopdf.render("<h1>doc #{i}</h1>") end,
          timeout: 60_000
        )
        |> Enum.map(fn {:ok, result} -> result end)

      assert Enum.all?(results, &match?({:ok, <<"%PDF-", _::binary>>}, &1))
    end
  end
end
