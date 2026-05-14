defmodule GuardedStructTest.AtomicVerifierTest do
  use ExUnit.Case, async: true

  alias GuardedStruct.AtomicClassifier
  alias GuardedStruct.Verifiers.VerifyAtomic
  alias GuardedStruct.Dsl.{Field, SubField, ConditionalField, VirtualField}

  defp dsl_state(module, entities, opts \\ []) do
    %{
      [:guardedstruct] => %{entities: entities, opts: opts},
      persist: %{module: module}
    }
  end

  defp ops(validate, sanitize \\ []) do
    %{validate: validate, sanitize: sanitize}
  end

  describe "atomic: false (default)" do
    test "any combination of unsafe ops is allowed when atomic is off" do
      state =
        dsl_state(NotAtomicMod, [
          %Field{name: :email, __derive_ops__: ops([:email])}
        ])

      assert :ok = VerifyAtomic.verify(state)
    end

    test "explicit atomic: false also skips verification" do
      state =
        dsl_state(
          OffMod,
          [%Field{name: :email, __derive_ops__: ops([:email])}],
          atomic: false
        )

      assert :ok = VerifyAtomic.verify(state)
    end
  end

  describe "atomic: true — happy paths" do
    test "pure-validate fields pass" do
      state =
        dsl_state(
          AllSafeMod,
          [
            %Field{name: :email, __derive_ops__: ops([:email_r, {:max_len, 320}])},
            %Field{name: :age, __derive_ops__: ops([:integer, {:min_len, 0}])},
            %Field{name: :name, __derive_ops__: ops([:string, :not_empty])}
          ],
          atomic: true
        )

      assert :ok = VerifyAtomic.verify(state)
    end

    test "sanitize + validate combos pass (sanitize runs before SQL)" do
      state =
        dsl_state(
          SanOkMod,
          [
            %Field{
              name: :email,
              __derive_ops__: ops([:email_r], [:trim, :downcase])
            },
            %Field{
              name: :role,
              __derive_ops__: ops([{:enum, ["admin", "user"]}], [:trim])
            }
          ],
          atomic: true
        )

      assert :ok = VerifyAtomic.verify(state)
    end

    test "all built-in sanitize ops are safe" do
      state =
        dsl_state(
          SanitizersOkMod,
          [
            %Field{
              name: :body,
              __derive_ops__:
                ops(
                  [:string],
                  [:trim, :downcase, :upcase, :capitalize, :strip_tags, :basic_html, :html5]
                )
            }
          ],
          atomic: true
        )

      assert :ok = VerifyAtomic.verify(state)
    end
  end

  describe "atomic: true — DNS validators rejected" do
    test "validate(email) blocked with DNS reason" do
      state =
        dsl_state(
          DnsEmailMod,
          [%Field{name: :email, __derive_ops__: ops([:email])}],
          atomic: true
        )

      assert {:error, err} = VerifyAtomic.verify(state)
      msg = Exception.message(err)

      assert msg =~ "atomic: true"
      assert msg =~ ":email"
      assert msg =~ "DNS"
      assert msg =~ "validate(email_r)"
    end

    test "validate(url) blocked with DNS/port reason" do
      state =
        dsl_state(
          DnsUrlMod,
          [%Field{name: :homepage, __derive_ops__: ops([:url])}],
          atomic: true
        )

      assert {:error, err} = VerifyAtomic.verify(state)
      msg = Exception.message(err)

      assert msg =~ ":homepage"
      assert msg =~ "DNS"
      assert msg =~ "validate(url_r)"
    end
  end

  describe "atomic: true — Elixir MFAs rejected" do
    test "per-field validator: {Mod, :fn} blocked" do
      state =
        dsl_state(
          PerFieldVMod,
          [
            %Field{
              name: :code,
              __derive_ops__: ops([:string]),
              validator: {Some.Mod, :check}
            }
          ],
          atomic: true
        )

      assert {:error, err} = VerifyAtomic.verify(state)
      msg = Exception.message(err)

      assert msg =~ ":code"
      assert msg =~ "validator:"
      assert msg =~ "arbitrary Elixir"
    end

    test "auto: {Mod, :fn} blocked" do
      state =
        dsl_state(
          AutoMfaMod,
          [
            %Field{
              name: :id,
              __derive_ops__: ops([:string]),
              auto: {Some.Gen, :gen}
            }
          ],
          atomic: true
        )

      assert {:error, err} = VerifyAtomic.verify(state)
      msg = Exception.message(err)

      assert msg =~ ":id"
      assert msg =~ "auto:"
      assert msg =~ "arbitrary Elixir"
    end

    test "section main_validator: option blocked" do
      state =
        dsl_state(
          MainValOptMod,
          [%Field{name: :a, __derive_ops__: ops([:string])}],
          atomic: true,
          main_validator: {Some.Validator, :check}
        )

      assert {:error, err} = VerifyAtomic.verify(state)
      msg = Exception.message(err)

      assert msg =~ "main_validator"
      assert msg =~ "cross-field"
    end
  end

  describe "atomic: true — cross-field options rejected" do
    test "field with `on:` cross-field dep blocked" do
      state =
        dsl_state(
          OnDepMod,
          [
            %Field{
              name: :parent_email,
              __derive_ops__: ops([:email_r]),
              on: "root::account_type"
            }
          ],
          atomic: true
        )

      assert {:error, err} = VerifyAtomic.verify(state)
      msg = Exception.message(err)

      assert msg =~ ":parent_email"
      assert msg =~ "on:"
    end

    test "field with `from:` reference blocked" do
      state =
        dsl_state(
          FromRefMod,
          [
            %Field{
              name: :copy,
              __derive_ops__: ops([:string]),
              from: "root::source"
            }
          ],
          atomic: true
        )

      assert {:error, err} = VerifyAtomic.verify(state)
      msg = Exception.message(err)

      assert msg =~ ":copy"
      assert msg =~ "from:"
    end

    test "field with `domain:` constraint blocked" do
      state =
        dsl_state(
          DomainMod,
          [
            %Field{
              name: :child_email,
              __derive_ops__: ops([:email_r]),
              domain: "!parent_email=Email[type=*]"
            }
          ],
          atomic: true
        )

      assert {:error, err} = VerifyAtomic.verify(state)
      msg = Exception.message(err)

      assert msg =~ ":child_email"
      assert msg =~ "domain:"
    end
  end

  describe "atomic: true — multiple blockers aggregate" do
    test "every offending field appears in one error message" do
      state =
        dsl_state(
          MultiFailMod,
          [
            %Field{name: :email, __derive_ops__: ops([:email])},
            %Field{name: :homepage, __derive_ops__: ops([:url])},
            %Field{
              name: :code,
              __derive_ops__: ops([:string]),
              validator: {Some.Mod, :check}
            }
          ],
          atomic: true
        )

      assert {:error, err} = VerifyAtomic.verify(state)
      msg = Exception.message(err)

      assert msg =~ ":email"
      assert msg =~ ":homepage"
      assert msg =~ ":code"
    end
  end

  describe "atomic: true — sub_field cascade" do
    test "unsafe op inside a sub_field is caught with full path" do
      state =
        dsl_state(
          SubFieldMod,
          [
            %SubField{
              name: :profile,
              fields: [
                %Field{name: :email, __derive_ops__: ops([:email])}
              ]
            }
          ],
          atomic: true
        )

      assert {:error, err} = VerifyAtomic.verify(state)
      msg = Exception.message(err)

      assert msg =~ ":profile"
      assert msg =~ ":email"
    end

    test "sub_field's own derive ops are also checked" do
      state =
        dsl_state(
          SubFieldOwnMod,
          [
            %SubField{
              name: :auth,
              __derive_ops__: ops([:email]),
              fields: []
            }
          ],
          atomic: true
        )

      assert {:error, err} = VerifyAtomic.verify(state)
      assert Exception.message(err) =~ ":auth"
    end
  end

  describe "atomic: true — virtual_field / conditional_field cascade" do
    test "unsafe op in a virtual_field is caught" do
      state =
        dsl_state(
          VirtualMod,
          [%VirtualField{name: :token, __derive_ops__: ops([:email])}],
          atomic: true
        )

      assert {:error, err} = VerifyAtomic.verify(state)
      assert Exception.message(err) =~ ":token"
    end

    test "unsafe op in a conditional_field child is caught" do
      state =
        dsl_state(
          CondMod,
          [
            %ConditionalField{
              name: :payload,
              fields: [%Field{name: :payload, __derive_ops__: ops([:email])}]
            }
          ],
          atomic: true
        )

      assert {:error, err} = VerifyAtomic.verify(state)
      assert Exception.message(err) =~ ":payload"
    end
  end

  describe "AtomicClassifier" do
    test "safe sanitize ops" do
      for op <- [:trim, :downcase, :upcase, :capitalize, :strip_tags, :basic_html, :html5] do
        assert AtomicClassifier.classify_op({:sanitize, op}) == :safe,
               "expected sanitize(#{op}) to be safe"
      end
    end

    test "safe validate ops — type checks" do
      for op <- [:string, :integer, :float, :boolean, :atom, :list, :map, :tuple, :record] do
        assert AtomicClassifier.classify_op({:validate, op}) == :safe
      end
    end

    test "safe validate ops — emptiness/length" do
      assert :safe = AtomicClassifier.classify_op({:validate, :not_empty})
      assert :safe = AtomicClassifier.classify_op({:validate, :not_empty_string})
      assert :safe = AtomicClassifier.classify_op({:validate, {:max_len, 80}})
      assert :safe = AtomicClassifier.classify_op({:validate, {:min_len, 0}})
    end

    test "safe validate ops — regex/pattern" do
      assert :safe = AtomicClassifier.classify_op({:validate, :uuid})
      assert :safe = AtomicClassifier.classify_op({:validate, :email_r})
      assert :safe = AtomicClassifier.classify_op({:validate, :url_r})
      assert :safe = AtomicClassifier.classify_op({:validate, :ipv4})
      assert :safe = AtomicClassifier.classify_op({:validate, {:regex, ~r/x/}})
    end

    test "safe validate ops — date/time" do
      for op <- [:datetime, :date, :time] do
        assert AtomicClassifier.classify_op({:validate, op}) == :safe
      end
    end

    test "safe validate ops — enum/equal/min/max" do
      assert :safe = AtomicClassifier.classify_op({:validate, {:enum, ["a", "b"]}})
      assert :safe = AtomicClassifier.classify_op({:validate, {:equal, "x"}})
      assert :safe = AtomicClassifier.classify_op({:validate, {:min, 0}})
      assert :safe = AtomicClassifier.classify_op({:validate, {:max, 100}})
    end

    test "unsafe DNS validators rejected with informative reasons" do
      assert {:unsafe, msg} = AtomicClassifier.classify_op({:validate, :email})
      assert msg =~ "DNS"
      assert msg =~ "email_r"

      assert {:unsafe, msg2} = AtomicClassifier.classify_op({:validate, :url})
      assert msg2 =~ "DNS"
      assert msg2 =~ "url_r"
    end

    test "unknown validate ops are rejected with a contributor-friendly catch-all" do
      assert {:unsafe, msg} = AtomicClassifier.classify_op({:validate, :totally_unknown})
      assert msg =~ "atomic-safe registry"
      assert msg =~ "AtomicClassifier"
    end

    test "custom sanitize ops (non-built-ins) are rejected" do
      assert {:unsafe, msg} = AtomicClassifier.classify_op({:sanitize, :slugify})
      assert msg =~ "Derive.Extension"
    end

    test "unrecognized shape returns a generic unsafe" do
      assert {:unsafe, msg} = AtomicClassifier.classify_op({:something, :weird})
      assert msg =~ "unrecognized"
    end
  end
end
