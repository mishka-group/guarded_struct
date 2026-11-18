defmodule GuardedStructTest.SubFieldDocHtmlTest do
  # Runs the real ExDoc on the fixture beams of test/support/fixtures/extracted/sub_field_doc.ex.
  # async: false — ExDoc keeps its references in a named ETS table.
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  @moduletag :ex_doc
  @moduletag :tmp_dir

  @prefix "GuardedStructTest.Fixtures.SubFieldDoc"
  # The fixtures of test/support/fixtures/extracted/typedoc.ex.
  @typedoc_prefix "GuardedStructTest.Fixtures.Typedoc"

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

    for prefix <- [@prefix, @typedoc_prefix],
        beam <- Path.wildcard(Path.join(ebin, "Elixir.#{prefix}*.beam")) do
      File.cp!(beam, Path.join(beams, Path.basename(beam)))
    end

    warnings =
      capture_io(:stderr, fn ->
        ExDoc.generate("guarded_struct_fixtures", "0.0.0", [beams],
          formatters: ["html"],
          output: html,
          api_reference: false,
          # The fixture beams belong to :guarded_struct; link them as local pages.
          apps: [:guarded_struct],
          main: "#{@prefix}Parent"
        )
      end)

    %{html: html, warnings: warnings}
  end

  defp page(html, module), do: Path.join(html, "#{@prefix}#{module}.html")

  defp typedoc_page(html, module),
    do: File.read!(Path.join(html, "#{@typedoc_prefix}#{module}.html"))

  # The rendered docs of the t() type: its spec and its @typedoc.
  defp t_section(page) do
    [_, section] = Regex.run(~r/<section class="detail" id="t:t\/0">(.*?)<\/section>/s, page)
    section
  end

  defp rows(section) do
    ~r/<tr>(.*?)<\/tr>/s
    |> Regex.scan(section, capture: :all_but_first)
    |> Enum.map(fn [row] ->
      ~r/<td[^>]*>(.*?)<\/td>/s |> Regex.scan(row, capture: :all_but_first) |> List.flatten()
    end)
    |> Enum.reject(&(&1 == []))
  end

  defp row(section, name), do: Enum.find(rows(section), &(hd(&1) =~ ">#{name}<"))

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

  describe "the t() type" do
    test "has a table of the fields under its spec", %{html: html} do
      section = html |> typedoc_page("Parent") |> t_section()

      assert section =~ "<th"
      assert section =~ "Required"

      assert [_, type, "yes", "", doc, derives] = row(section, ":name")
      assert type =~ "String.t()"
      assert derives =~ "sanitize(trim) validate(string)"
      assert doc == "The name; a | pipe stays in its cell."

      assert [_, _type, "no", default | _] = row(section, ":count")
      assert default =~ "0"
    end

    test "links each struct type of the table to its page", %{html: html} do
      section = html |> typedoc_page("Parent") |> t_section()

      assert [_, address | _] = row(section, ":address")
      assert address =~ ~s(href="#{@typedoc_prefix}Address.html#t:t/0")

      assert [_, profile | _] = row(section, ":profile")
      assert profile =~ ~s(href="#{@typedoc_prefix}Parent.Profile.html#t:t/0")

      assert [_, plan | _] = row(section, ":plan")
      assert plan =~ ~s(href="#{@typedoc_prefix}Parent.Plan1.html#t:t/0")
      assert plan =~ ~s(href="#{@typedoc_prefix}Address.html#t:t/0")
    end

    test "links the nested types in the spec", %{html: html} do
      section = html |> typedoc_page("Parent") |> t_section()

      [_, spec] =
        Regex.run(
          ~r/<pre translate="no"><span class="attribute">@type<\/span>(.*?)<\/pre>/s,
          section
        )

      assert spec =~ ~s(href="#{@typedoc_prefix}Address.html#t:t/0")
      assert spec =~ ~s(href="#{@typedoc_prefix}Parent.Lines.html#t:t/0")
    end

    test "a generated sub_field page has its own table", %{html: html} do
      section = html |> typedoc_page("Parent.Profile") |> t_section()
      assert [_, _, "no", "", "A short bio.", ""] = row(section, ":bio")
    end

    test "a block-less sub_field links to the user's own module", %{html: html} do
      section = html |> typedoc_page("Uses") |> t_section()
      assert [_, address | _] = row(section, ":address")
      assert address =~ ~s(href="#{@typedoc_prefix}Uses.Address.html#t:t/0")

      items = typedoc_page(html, "Uses.Items")
      assert items =~ "own item module, in another file."
      assert t_section(items) =~ "One item, as the user describes it."
    end

    test "the user's own @typedoc is shown instead of the table", %{html: html} do
      section = html |> typedoc_page("OwnTypedoc") |> t_section()
      assert section =~ "My own words about t."
      refute section =~ "<table"
    end

    test "ExDoc has no warning about the links", %{warnings: warnings} do
      assert warnings == ""
    end
  end
end
