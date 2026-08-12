# Renders a small invoice with headers/footers and page numbers to /tmp.
#
# Run from the project root:
#
#     EXSGHTMLTOPDF_BUILD=1 mix run examples/invoice.exs

html = """
<!doctype html>
<html>
  <head>
    <style>
      body { font-family: sans-serif; margin: 0; }
      h1 { border-bottom: 2px solid #333; padding-bottom: 8px; }
      table { width: 100%; border-collapse: collapse; margin-top: 24px; }
      th { text-align: left; background: #f0f0f0; }
      th, td { padding: 8px; border-bottom: 1px solid #ddd; }
      td.amount, th.amount { text-align: right; }
      tfoot td { font-weight: bold; border-top: 2px solid #333; }
      .grid { display: grid; grid-template-columns: 1fr 1fr; gap: 16px; margin-top: 16px; }
    </style>
  </head>
  <body>
    <h1>Invoice #2026-081</h1>
    <div class="grid">
      <div><strong>From:</strong><br />Example Pty Ltd</div>
      <div><strong>To:</strong><br />Customer Co</div>
    </div>
    <table>
      <thead>
        <tr><th>Item</th><th class="amount">Amount</th></tr>
      </thead>
      <tbody>
        <tr><td>HTML to PDF rendering</td><td class="amount">$100.00</td></tr>
        <tr><td>No headless browser surcharge</td><td class="amount">$0.00</td></tr>
      </tbody>
      <tfoot>
        <tr><td>Total</td><td class="amount">$100.00</td></tr>
      </tfoot>
    </table>
  </body>
</html>
"""

path = "/tmp/ex_sghtmltopdf_invoice.pdf"

:ok =
  ExSghtmltopdf.render_to_file(html, path,
    page_size: "A4",
    margin_top: "20mm",
    margin_bottom: "20mm",
    header_right: "Example Pty Ltd",
    footer_center: "Page [page] of [topage]"
  )

{:ok, pdf} = ExSghtmltopdf.render(html)

IO.puts("Wrote #{path} (#{File.stat!(path).size} bytes)")

IO.puts(
  "In-memory render: #{byte_size(pdf)} bytes, starts with #{inspect(binary_part(pdf, 0, 8))}"
)
