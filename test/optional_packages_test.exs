defmodule GuardedStructTest.OptionalPackagesTest do
  # Hides a package from the code path, so it must not run beside the async suites.
  use ExUnit.Case, async: false

  alias GuardedStruct.Derive.ValidationDerive
  alias GuardedStruct.Validate

  defmodule Contact do
    use GuardedStruct

    guardedstruct do
      field(:phone, String.t(), derives: "validate(tell)")
      field(:mobile, String.t(), derives: "validate(tell=98)")
      field(:place, String.t(), derives: "validate(geo_url)")
      field(:email, String.t(), derives: "validate(email)")
      field(:email_r, String.t(), derives: "validate(email_r)")
    end
  end

  defp without_package(app, module, fun) do
    ebin = Application.app_dir(app, "ebin")
    Code.delete_path(ebin)
    :code.purge(module)
    :code.delete(module)
    :code.purge(module)

    try do
      fun.()
    after
      Code.prepend_path(ebin)
    end
  end

  describe "a package that is installed" do
    test "is used whenever the op runs" do
      assert "+989368090000" = ValidationDerive.validate({:tell, 98}, "+989368090000", :mobile)
      assert "09368090000" = ValidationDerive.validate(:tell, "09368090000", :mobile)
      assert "info@gmail.com" = ValidationDerive.validate(:email, "info@gmail.com", :email)
    end

    test "is looked up when the op runs, not when GuardedStruct was compiled" do
      assert {:error, :phone, :tell, msg} =
               without_package(:ex_url, URL, fn ->
                 ValidationDerive.validate(:tell, "09368090000", :phone)
               end)

      assert msg =~ ":ex_url"
      assert "09368090000" = ValidationDerive.validate(:tell, "09368090000", :phone)
    end
  end

  describe "a package that is missing" do
    test "ex_url: tell, geo_url and location name the package to add" do
      without_package(:ex_url, URL, fn ->
        for op <- [:tell, :geo_url, :location] do
          assert {:error, :field, ^op, msg} = ValidationDerive.validate(op, "1,2", :field)
          assert msg =~ ~s({:ex_url, "~> 2.0"})
        end

        assert {:error, :mobile, :tell, msg} =
                 ValidationDerive.validate({:tell, 98}, "+989368090000", :mobile)

        assert msg =~ ":ex_url"
      end)
    end

    test "ex_phone_number: the country code form names it" do
      without_package(:ex_phone_number, ExPhoneNumber, fn ->
        assert {:error, :mobile, :tell, msg} =
                 ValidationDerive.validate({:tell, 98}, "+989368090000", :mobile)

        assert msg =~ ~s({:ex_phone_number, "~> 0.4"})
      end)
    end

    test "email_checker: validate(email) names it and validate(email_r) is unaffected" do
      without_package(:email_checker, EmailChecker, fn ->
        assert {:error, :email, :email, msg} =
                 ValidationDerive.validate(:email, "info@gmail.com", :email)

        assert msg =~ ~s({:email_checker, "~> 0.2"})
        assert "info@gmail.com" = ValidationDerive.validate(:email_r, "info@gmail.com", :email)
      end)
    end

    test "the error reaches builder/1 and Validate.run/2 as a normal error" do
      without_package(:ex_url, URL, fn ->
        assert {:error, errors} =
                 Contact.builder(%{phone: "09368090000", email_r: "info@gmail.com"})

        assert [%{field: :phone, action: :tell, message: msg}] = errors
        assert msg =~ ":ex_url"

        assert {:error, [%{field: :__value__, action: :geo_url, message: msg}]} =
                 Validate.run("validate(geo_url)", "48.198634,-16.371648")

        assert msg =~ ":ex_url"
      end)
    end
  end
end
