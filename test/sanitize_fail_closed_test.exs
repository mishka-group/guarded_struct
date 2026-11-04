defmodule GuardedStructTest.SanitizeFailClosedTest do
  @moduledoc """
  Sanitizing fails closed: a sanitizer that raises fails its field instead of
  keeping the raw value, and an op that nothing serves raises `ArgumentError`.
  """
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Ash.Error.Changes.InvalidAttribute
  alias GuardedStruct.Derive.{Registry, SanitizerDerive}

  # Invalid UTF-8 makes the unicode regex of `no_zero_width` (and so
  # `rich_text_safe`) raise inside the built-in op.
  @invalid_utf8 <<"<b>top-secret</b>", 0xFF>>

  defmodule PassesOn do
    def sanitize(_input, _op), do: nil
  end

  defmodule Exploding do
    def sanitize(_input, :explode), do: raise("sanitizer blew up")
  end

  defmodule Shouting do
    def sanitize(input, :shout), do: String.upcase(input)
  end

  defmodule Post do
    use GuardedStruct

    guardedstruct sanitize_derive: [PassesOn, Exploding, Shouting] do
      field(:body, String.t(), derives: "sanitize(rich_text_safe) validate(string)")
      field(:custom, String.t(), derives: "sanitize(explode) validate(string)")
      field(:title, String.t(), derives: "sanitize(trim, shout) validate(string)")
      field(:tags, list(String.t()), derives: "sanitize(each=[trim, rich_text_safe])")
      field(:typo, String.t(), derives: "sanitize(no_such_op)")
    end
  end

  defmodule Plain do
    use GuardedStruct

    guardedstruct do
      field(:typo, String.t(), derives: "sanitize(trim, no_such_op)")
    end
  end

  defmodule Article do
    use Ash.Resource,
      domain: GuardedStructTest.Support.TestDomain,
      data_layer: Ash.DataLayer.Ets,
      extensions: [GuardedStruct.AshResource]

    ets do
      private? true
    end

    guardedstruct do
      auto_wire true
      sanitize_derive GuardedStructTest.SanitizeFailClosedTest.Exploding

      field :body, :string, derives: "sanitize(explode) validate(string)"
      field :title, :string, derives: "sanitize(trim) validate(string)"
    end

    actions do
      defaults [:read]
      create :create, accept: [:body, :title]
    end

    attributes do
      uuid_primary_key :id
      attribute :body, :string, public?: true
      attribute :title, :string, public?: true
    end
  end

  setup do
    saved = Application.get_env(:guarded_struct, :sanitize_derive)
    Application.delete_env(:guarded_struct, :sanitize_derive)

    on_exit(fn ->
      if saved, do: Application.put_env(:guarded_struct, :sanitize_derive, saved)
    end)
  end

  describe "a sanitizer that raises" do
    test "a built-in op fails the field instead of keeping the raw value" do
      {result, _log} = with_log(fn -> Post.builder(%{body: @invalid_utf8, title: " hi "}) end)

      assert {:error, [%{field: :body, action: :sanitize, message: message}]} = result
      assert message =~ "could not be sanitized"
    end

    test "a sanitize_derive module fails the field the same way" do
      {result, _log} = with_log(fn -> Post.builder(%{custom: "<script>alert(1)</script>"}) end)

      assert {:error, [%{field: :custom, action: :sanitize, message: message}]} = result
      assert message =~ "could not be sanitized"
    end

    test "one bad item of an each= list fails the whole field" do
      {result, _log} = with_log(fn -> Post.builder(%{tags: [" ok ", @invalid_utf8]}) end)

      assert {:error, [%{field: :tags, action: :sanitize}]} = result
    end

    test "the exception and its stacktrace are logged, the value is not" do
      {_result, builtin_log} = with_log(fn -> Post.builder(%{body: @invalid_utf8}) end)

      assert builtin_log =~ "[error]"
      assert builtin_log =~ "ArgumentError"
      assert builtin_log =~ ":rich_text_safe"
      refute builtin_log =~ "top-secret"
      refute builtin_log =~ inspect(@invalid_utf8)

      {_result, custom_log} =
        with_log(fn -> Post.builder(%{custom: "<script>alert(1)</script>"}) end)

      assert custom_log =~ "sanitizer blew up"
      assert custom_log =~ inspect(Exploding)
      refute custom_log =~ "alert(1)"
    end

    test "an Ash action returns it as an invalid attribute at the field" do
      {result, _log} =
        with_log(fn ->
          Article
          |> Ash.Changeset.for_create(:create, %{body: "<script>x</script>", title: "ok"})
          |> Ash.create()
        end)

      assert {:error, %Ash.Error.Invalid{errors: [%InvalidAttribute{} = error]}} = result
      assert %{field: :body, vars: [validation: :sanitize]} = error
      assert error.message =~ "could not be sanitized"
    end

    test "sanitize/2 called directly raises the exception" do
      assert_raise ArgumentError, fn ->
        SanitizerDerive.sanitize(@invalid_utf8, :rich_text_safe)
      end

      Application.put_env(:guarded_struct, :sanitize_derive, Exploding)

      assert_raise RuntimeError, "sanitizer blew up", fn ->
        SanitizerDerive.sanitize("x", :explode)
      end
    end
  end

  describe "an op nothing serves" do
    test "raises ArgumentError in a module without sanitize_derive" do
      assert_raise ArgumentError, ~r/:no_such_op/, fn -> Plain.builder(%{typo: "x"}) end
    end

    test "raises ArgumentError when no sanitize_derive module serves it" do
      assert_raise ArgumentError, ~r/:no_such_op/, fn -> Post.builder(%{typo: "x"}) end
    end

    test "raises ArgumentError from sanitize/2" do
      assert_raise ArgumentError, ~r/:no_such_op/, fn ->
        SanitizerDerive.sanitize("x", :no_such_op)
      end
    end

    test "the message does not quote the value" do
      error = assert_raise ArgumentError, fn -> Plain.builder(%{typo: "top-secret"}) end
      refute Exception.message(error) =~ "top-secret"
    end
  end

  describe "valid input" do
    @html "<p>Hi <b>there</b></p><script>alert(1)</script>"

    @cases [
      {:trim, "  a b  ", "a b"},
      {:trim, 5, 5},
      {:upcase, "abc", "ABC"},
      {:downcase, "ABC", "abc"},
      {:capitalize, "abc def", "Abc def"},
      {:basic_html, @html, HtmlSanitizeEx.basic_html(@html)},
      {:html5, @html, HtmlSanitizeEx.html5(@html)},
      {:html5, 5, 5},
      {:markdown_html, @html, HtmlSanitizeEx.markdown_html(@html)},
      {:strip_tags, @html, HtmlSanitizeEx.strip_tags(@html)},
      {:strip_tags, nil, nil},
      {{:tag, :strip_tags}, " <b>x</b> ", "x"},
      {{:tag, "strip_tags"}, " <b>x</b> ", "x"},
      {{:tag, :strip_tags}, 5, 5},
      {:string_float, "<p>12.5</p>", 12.5},
      {:string_float, "abc", 0.0},
      {:string_float, 3.5, 3.5},
      {:string_integer, "<p>12</p>", 12},
      {:string_integer, 7, 7},
      {:uniq, [1, 1, 2], [1, 2]},
      {:uniq, "a", "a"},
      {:compact, [1, nil, 2], [1, 2]},
      {:reject_empty, [nil, "", [], %{}, "a"], ["a"]},
      {:sort, [3, 1, 2], [1, 2, 3]},
      {:squish, "  a   b \n c ", "a b c"},
      {:no_control, "a\x00b\tc", "ab\tc"},
      {:no_zero_width, "a​b", "ab"},
      {:rich_text_safe, "a​\x01b", "ab"},
      {{:clamp, [0, 10]}, 15, 10},
      {{:clamp, [0, 10]}, -1, 0},
      {{:clamp, [0, 10]}, "x", "x"},
      {{:default_when_nil, "x"}, nil, "x"},
      {{:default_when_nil, "x"}, "y", "y"},
      {{:default_when_empty, "x"}, "", "x"},
      {{:default_when_empty, "x"}, "y", "y"},
      {{:each, [:trim, :upcase]}, [" a ", "b "], ["A", "B"]},
      {{:each, [:trim]}, "a", "a"},
      {%{each: [:trim]}, [" a "], ["a"]}
    ]

    test "every built-in op is covered below" do
      names =
        MapSet.new(@cases, fn
          {%{each: _}, _, _} -> :each
          {{name, _}, _, _} -> name
          {name, _, _} -> name
        end)

      assert names == Registry.sanitize_ops()
    end

    test "every built-in op returns the sanitized value, directly and in a derive" do
      for {op, input, expected} <- @cases do
        assert SanitizerDerive.sanitize(input, op) == expected, inspect({op, input})
        assert SanitizerDerive.call({:field, input}, [op]) == {:field, expected}, inspect(op)
      end
    end

    test "a sanitize_derive module that returns nil passes the op to the next one" do
      assert {:ok, %Post{title: "HI"}} = Post.builder(%{title: "  hi "})
    end

    test "each= sanitizes every item of a list" do
      assert {:ok, %Post{tags: ["a", "b"]}} = Post.builder(%{tags: [" a ", "b​"]})
    end

    test "an Ash action stores the sanitized value" do
      assert {:ok, %{title: "ok"}} =
               Article
               |> Ash.Changeset.for_create(:create, %{title: "  ok  "})
               |> Ash.create()
    end
  end
end
