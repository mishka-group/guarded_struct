defmodule GuardedStructTest.SubFieldDocHtmlTest do
  # Runs the real ExDoc on the fixture beams of test/support/fixtures/extracted/sub_field_doc.ex.
  # async: false — ExDoc keeps its references in a named ETS table.
  use ExUnit.Case, async: false

  @moduletag :ex_doc
  @moduletag :tmp_dir

  @prefix "GuardedStructTest.Fixtures.SubFieldDoc"

  setup_all do
    {:ok, _} = Application.ensure_all_started(:ex_doc)
    :ok
  end

  setup %{tmp_dir: tmp_dir} do
    beams = Path.join(tmp_dir, "beams")
    html = Path.join(tmp_dir, "html")
    File.mkdir_p!(beams)

    # Only the fixture beams, so ExDoc reads a handful of modules instead of the whole ebin.
    ebin = Path.join(Mix.Project.app_path(), "ebin")

    for beam <- Path.wildcard(Path.join(ebin, "Elixir.#{@prefix}*.beam")) do
      File.cp!(beam, Path.join(beams, Path.basename(beam)))
    end

    ExDoc.generate("guarded_struct_fixtures", "0.0.0", [beams],
      formatters: ["html"],
      output: html,
      api_reference: false,
      main: "#{@prefix}Parent"
    )

    %{html: html}
  end

  defp page(html, module), do: Path.join(html, "#{@prefix}#{module}.html")

  defp moduledoc_html(html, module) do
    case Regex.run(~r/<section id="moduledoc">(.*?)<\/section>/s, File.read!(page(html, module))) do
      [_, inner] -> String.trim(inner)
      nil -> nil
    end
  end

  test "each sub_field with doc: gets a page that shows its doc", %{html: html} do
    assert moduledoc_html(html, ".Transaction") =~ "One movement of the seller"

    assert moduledoc_html(html, ".Transaction.Fee") ==
             "<p>The fee taken from one transaction.</p>"

    assert moduledoc_html(html, ".Lines") == "<p>One line of the order.</p>"
    assert moduledoc_html(html, ".Plan1") == "<p>A plan given in detail.</p>"
    assert moduledoc_html(html, ".Setter") == "<p>Set with the setter form inside the block.</p>"
  end

  test "the doc is rendered as Markdown", %{html: html} do
    assert moduledoc_html(html, "Parent.Child") =~ "<strong>own</strong>"
  end

  test "the parent's page shows only the parent's own doc", %{html: html} do
    assert moduledoc_html(html, "Parent") == "<p>The parent's own doc.</p>"
  end

  test "doc: false has no page", %{html: html} do
    refute File.exists?(page(html, ".Internal"))
    assert File.exists?(page(html, ".Plain"))
  end

  test "without doc: the page has no doc section", %{html: html} do
    assert moduledoc_html(html, ".Plain") == nil
    assert moduledoc_html(html, "NoParentDoc") in [nil, ""]
  end
end
