defmodule GuardedStructTest.DeriveTest do
  use ExUnit.Case, async: true
  alias GuardedStruct.Derive.{SanitizerDerive, ValidationDerive}

  ############## (▰˘◡˘▰) Sanitizer Derive (▰˘◡˘▰) ##############
  test "sanitize(:trim, input)" do
    "Mishka Group" = assert SanitizerDerive.sanitize("  Mishka Group  ", :trim)
  end

  test "sanitize(:upcase, input)" do
    "MISHKA GROUP" = assert SanitizerDerive.sanitize("Mishka Group", :upcase)
  end

  test "sanitize(:downcase, input)" do
    "mishka group" = assert SanitizerDerive.sanitize("MISHKA GROUP", :downcase)
  end

  test "sanitize(:capitalize, input)" do
    "Mishka group" = assert SanitizerDerive.sanitize("mishka group", :capitalize)
  end

  test "sanitize(:basic_html, input)" do
    "<p>Hi Shahryar</p>" = assert SanitizerDerive.sanitize("<p>Hi Shahryar</p>", :basic_html)
  end

  test "sanitize(:html5, input)" do
    "<section>Hi Shahryar</section>" =
      assert SanitizerDerive.sanitize("<section>Hi Shahryar</section>", :html5)
  end

  test "sanitize(input, :markdown_html)" do
    "[Mishka Group](https://mishka.tools)" =
      assert SanitizerDerive.sanitize("[Mishka Group](https://mishka.tools)", :markdown_html)
  end

  test "sanitize(input, :strip_tags)" do
    "Hi Shahryar" = assert SanitizerDerive.sanitize("<p>Hi Shahryar</p>", :strip_tags)
  end

  test "sanitize(input, {:tag, :op})" do
    "Hi Shahryar" = assert SanitizerDerive.sanitize("<p>Hi Shahryar</p>", {:tag, :strip_tags})
  end

  test "sanitize(:not_exist, input)" do
    "<p>Hi Shahryar</p>" = assert SanitizerDerive.sanitize("<p>Hi Shahryar</p>", :not_exist)
  end

  test "sanitize(:string_float, input)" do
    2369.0 = assert SanitizerDerive.sanitize("<p>2369</p>", :string_float)
    3.0 = assert SanitizerDerive.sanitize("3s4s6.65", :string_float)
    346.65 = assert SanitizerDerive.sanitize("346.65sss", :string_float)
    346.65 = assert SanitizerDerive.sanitize("346.65", :string_float)
    346.65 = assert SanitizerDerive.sanitize(346.65, :string_float)
  end

  test "sanitize(:string_integer, input)" do
    2369 = assert SanitizerDerive.sanitize("<p>2369</p>", :string_integer)
    3 = assert SanitizerDerive.sanitize("3s4s6.65", :string_integer)
    346 = assert SanitizerDerive.sanitize("346.65sss", :string_integer)
    346 = assert SanitizerDerive.sanitize("346.65", :string_integer)
    346 = assert SanitizerDerive.sanitize(346, :string_integer)
    # We just sanitize string values
    346.6 = assert SanitizerDerive.sanitize(346.6, :string_integer)
  end

  ############## (▰˘◡˘▰) Validation Derive (▰˘◡˘▰) ##############
  test "validate(:string, input, field)" do
    "Mishka" = assert ValidationDerive.validate(:string, "Mishka", :title)
    {:error, :title, :string, _msg} = assert ValidationDerive.validate(:string, :test, :title)
  end

  test "validate(:integer, input, field)" do
    2 = assert ValidationDerive.validate(:integer, 2, :age)
    {:error, :age, :integer, _msg} = assert ValidationDerive.validate(:integer, :test, :age)
  end

  test "validate(:list, input, field)" do
    ["Mishka"] = assert ValidationDerive.validate(:list, ["Mishka"], :app_list)
    {:error, :app_list, :list, _msg} = assert ValidationDerive.validate(:list, :test, :app_list)
  end

  test "validate(:atom, input, field)" do
    :mishka = assert ValidationDerive.validate(:atom, :mishka, :app_atom)
    {:error, :app_atom, :atom, _msg} = assert ValidationDerive.validate(:atom, [:test], :app_atom)
  end

  test "validate(:bitstring, input, field)" do
    <<1::3>> = assert ValidationDerive.validate(:bitstring, <<1::3>>, :app_bitstring)

    {:error, :app_bitstring, :bitstring, _msg} =
      assert ValidationDerive.validate(:bitstring, [:test], :app_bitstring)
  end

  test "validate(:boolean, input, field)" do
    true = assert ValidationDerive.validate(:atom, true, :status)

    {:error, :status, :boolean, _msg} =
      assert ValidationDerive.validate(:boolean, [:test], :status)
  end

  test "validate(:exception, input, field)" do
    %RuntimeError{} = assert ValidationDerive.validate(:exception, %RuntimeError{}, :status)

    {:error, :status, :exception, _msg} =
      assert ValidationDerive.validate(:exception, [:test], :status)
  end

  test "validate(:float, input, field)" do
    1.233 = assert ValidationDerive.validate(:float, 1.233, :status)

    {:error, :status, :float, _msg} =
      assert ValidationDerive.validate(:float, 1, :status)
  end

  test "validate(:function, input, field)" do
    getfn = ValidationDerive.validate(:function, fn x -> x + x end, :status)
    true = assert is_function(getfn)

    {:error, :status, :function, _msg} =
      assert ValidationDerive.validate(:function, "not a function", :status)
  end

  test "validate(:map, input, field)" do
    %{name: "Shahryar"} = assert ValidationDerive.validate(:map, %{name: "Shahryar"}, :status)

    {:error, :status, :map, _msg} =
      assert ValidationDerive.validate(:map, 1, :status)
  end

  test "validate(:nil_value, input, field)" do
    get_nil = ValidationDerive.validate(:nil_value, nil, :status)
    true = assert is_nil(get_nil)

    {:error, :status, :nil_value, _msg} =
      assert ValidationDerive.validate(:nil_value, 1, :status)
  end

  test "validate(:not_nil_value, input, field)" do
    1 = assert ValidationDerive.validate(:not_nil_value, 1, :status)

    {:error, :status, :not_nil_value, _msg} =
      assert ValidationDerive.validate(:not_nil_value, nil, :status)
  end

  test "validate(:number, input, field)" do
    2 = assert ValidationDerive.validate(:number, 2, :age)
    {:error, :age, :number, _msg} = assert ValidationDerive.validate(:number, :test, :age)
  end

  test "validate(:pid, input, field)" do
    get_pid = ValidationDerive.validate(:pid, self(), :node)
    true = assert is_pid(get_pid)

    {:error, :node, :pid, _msg} = assert ValidationDerive.validate(:pid, :test, :node)
  end

  test "validate(:port, input, field)" do
    get_port = ValidationDerive.validate(:port, Port.open({:spawn, "cat"}, [:binary]), :node)
    true = assert is_port(get_port)

    {:error, :node, :port, _msg} = assert ValidationDerive.validate(:port, :test, :node)
  after
    File.rm("name")
  end

  test "validate(:reference, input, field)" do
    get_reference = ValidationDerive.validate(:reference, :erlang.make_ref(), :node)
    true = assert is_reference(get_reference)

    {:error, :node, :reference, _msg} = assert ValidationDerive.validate(:reference, :test, :node)
  end

  test "validate(:struct, input, field)" do
    %User{} = assert ValidationDerive.validate(:struct, %User{}, :node)

    {:error, :node, :struct, _msg} = assert ValidationDerive.validate(:struct, :test, :node)
  end

  test "validate(:tuple, input, field)" do
    {:ok} = assert ValidationDerive.validate(:tuple, {:ok}, :node)

    {:error, :node, :tuple, _msg} = assert ValidationDerive.validate(:tuple, :test, :node)
  end

  test "validate(:not_empty, input, field) -> string" do
    "Shahryar" = assert ValidationDerive.validate(:not_empty, "Shahryar", :name)
    {:error, :name, :not_empty, _msg} = assert ValidationDerive.validate(:not_empty, "", :name)
  end

  test "validate(:not_empty, input, field) -> list" do
    ["Shahryar"] = assert ValidationDerive.validate(:not_empty, ["Shahryar"], :name)
    {:error, :name, :not_empty, _msg} = assert ValidationDerive.validate(:not_empty, [], :name)
  end

  test "validate(:not_empty, input, field) -> map" do
    %{name: "Shahryar"} = assert ValidationDerive.validate(:not_empty, %{name: "Shahryar"}, :name)
    {:error, :name, :not_empty, _msg} = assert ValidationDerive.validate(:not_empty, %{}, :name)
  end

  test "validate({:max_len, len}, input, field) -> string" do
    "Shahryar" = assert ValidationDerive.validate({:max_len, 15}, "Shahryar", :name)

    {:error, :name, :max_len, _msg} =
      assert ValidationDerive.validate({:max_len, 2}, "Mishka", :name)
  end

  test "validate({:max_len, len}, input, field) -> integer" do
    14 = assert ValidationDerive.validate({:max_len, 15}, 14, :name)

    {:error, :name, :max_len, _msg} =
      assert ValidationDerive.validate({:max_len, 2}, 15, :name)
  end

  test "validate({:max_len, len}, input, field) -> range" do
    1..14 = assert ValidationDerive.validate({:max_len, 15}, 1..14, :name)

    {:error, :name, :max_len, _msg} =
      assert ValidationDerive.validate({:max_len, 2}, 1..3, :name)
  end

  test "validate({:min_len, len}, input, field) -> string" do
    "Shahryar" = assert ValidationDerive.validate({:min_len, 8}, "Shahryar", :name)

    {:error, :name, :min_len, _msg} =
      assert ValidationDerive.validate({:min_len, 15}, "Mishka", :name)
  end

  test "validate({:min_len, len}, input, field) -> integer" do
    15 = assert ValidationDerive.validate({:min_len, 14}, 15, :name)

    {:error, :name, :min_len, _msg} =
      assert ValidationDerive.validate({:min_len, 13}, 12, :name)
  end

  test "validate({:min_len, len}, input, field) -> range" do
    14..20 = assert ValidationDerive.validate({:min_len, 14}, 14..20, :name)

    {:error, :name, :min_len, _msg} =
      assert ValidationDerive.validate({:min_len, 13}, 12..16, :name)
  end

  test "validate(:url, input, field)" do
    "https://github.com/mishka-group/" =
      assert ValidationDerive.validate(:url, "https://github.com/mishka-group/", :name)

    "http://github.com/mishka-group/" =
      assert ValidationDerive.validate(:url, "http://github.com/mishka-group/", :name)

    {:error, :name, :url, _msg} =
      assert ValidationDerive.validate(:url, "www.github.com/mishka-group/", :name)

    {:error, :name, :url, _msg1} =
      assert ValidationDerive.validate(:url, :test, :name)
  end

  test "validate(:geo_url, input, field)" do
    {:error, :map, :geo_url, _msg1} =
      assert ValidationDerive.validate(:geo_url, :test, :map)

    "geo:48.198634,-16.371648,3.4;crs=wgs84;u=40.0" =
      assert ValidationDerive.validate(
               :geo_url,
               "48.198634,-16.371648,3.4;crs=wgs84;u=40.0",
               :map
             )

    {:error, :map, :geo_url, _msg2} =
      assert ValidationDerive.validate(
               :geo_url,
               "48.198634,--16.371648,3.4",
               :map
             )
  end

  test "validate(:tell, input, field)" do
    "09368090000" = assert ValidationDerive.validate(:tell, "09368090000", :mobile)

    {:error, :mobile, :tell, _msg} =
      assert ValidationDerive.validate(:tell, "09368090000ABC", :mobile)
  end

  test "validate({:tell, country_code}, input, field) -> country_code" do
    "+989368090000" = assert ValidationDerive.validate({:tell, 98}, "+989368090000", :mobile)

    {:error, :mobile, :tell, _msg} =
      assert ValidationDerive.validate({:tell, 98}, "09368090000ABC", :mobile)

    {:error, :mobile, :tell, _msg1} =
      assert ValidationDerive.validate({:tell, 98}, "00989368090000", :mobile)
  end

  test "validate(:email, input, field)" do
    "info@gmail.com" = assert ValidationDerive.validate(:email, "info@gmail.com", :email)

    {:error, :email, :email, _msg} =
      assert ValidationDerive.validate(:email, "info@gmailtestabcd2569.com", :email)

    {:error, :email, :email, _msg1} =
      assert ValidationDerive.validate(:email, :test, :email)
  end

  test "validate(:location, input, field)" do
    "geo:48.198634,-16.371648,3.4;crs=wgs84;u=40.0" =
      assert ValidationDerive.validate(
               :location,
               "48.198634,-16.371648,3.4;crs=wgs84;u=40.0",
               :location
             )

    "geo:48.198634,-16.371648" =
      assert ValidationDerive.validate(
               :location,
               "48.198634, -16.371648",
               :location
             )

    {:error, :location, :location, _msg1} =
      assert ValidationDerive.validate(
               :location,
               "48.198634, --16.371648",
               :location
             )
  end

  test "validate(:string_boolean, input, field)" do
    "true" = assert ValidationDerive.validate(:string_boolean, "true", :status)
    "false" = assert ValidationDerive.validate(:string_boolean, "false", :status)

    {:error, :status, :string_boolean, _msg} =
      assert ValidationDerive.validate(:string_boolean, "test", :status)
  end

  test "validate(:datetime, input, field)" do
    "2023-08-04 13:46:53.419944Z" =
      assert ValidationDerive.validate(:datetime, "2023-08-04 13:46:53.419944Z", :exp)

    "2023-07-15T12:00:00Z" =
      assert ValidationDerive.validate(:datetime, "2023-07-15T12:00:00Z", :exp)

    "2023-07-16T15:00:00Z" =
      assert ValidationDerive.validate(:datetime, "2023-07-16T15:00:00Z", :exp)

    "2023-07-16T15:00:00Z" =
      assert ValidationDerive.validate(:datetime, "2023-07-16T15:00:00Z", :exp)

    "2023-07-25T18:15:00Z" =
      assert ValidationDerive.validate(:datetime, "2023-07-25T18:15:00Z", :exp)

    {:error, :exp, :datetime, _msg} =
      assert ValidationDerive.validate(:datetime, "2023-08-04", :exp)
  end

  test "validate(:date, input, field)" do
    "2023-08-04" = assert ValidationDerive.validate(:date, "2023-08-04", :exp)

    {:error, :exp, :date, _msg} =
      assert ValidationDerive.validate(:date, "2023-07-25T18:15:00Z", :exp)
  end

  test "validate(:range, input, field)" do
    1..3 = assert ValidationDerive.validate(:range, 1..3, :age)
    {:error, :age, :range, _msg} = assert ValidationDerive.validate(:range, :test, :age)
  end

  test "validate({:regex, pattern_str}, input, field)" do
    "footer" = assert ValidationDerive.validate({:regex, ~c"foo"}, "footer", :element)

    "info@gmail.com" =
      assert ValidationDerive.validate(
               {:regex, ~c"^[A-Za-z0-9\._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,6}$"},
               "info@gmail.com",
               :email
             )

    {:error, :email, :regex, _msg} =
      assert ValidationDerive.validate({:regex, ~c"1"}, "info@gmail.com", :email)
  end

  test "validate(:not_empty_string, input, field)" do
    "mishka" = assert ValidationDerive.validate(:not_empty_string, "mishka", :name)

    {:error, :name, :not_empty_string, _msg} =
      assert ValidationDerive.validate(:not_empty_string, :test, :name)

    {:error, :name, :not_empty_string, _msg1} =
      assert ValidationDerive.validate(:not_empty_string, "", :name)
  end

  test "validate(:uuid, input, field)" do
    "d528ba1e-cd85-4f61-954c-7c8aa8e8decc" =
      assert ValidationDerive.validate(:uuid, "d528ba1e-cd85-4f61-954c-7c8aa8e8decc", :name)

    {:error, :id, :uuid, _msg} =
      assert ValidationDerive.validate(:uuid, "d528ba1e-cd85-4f61-954c1-7c8aa8e8decc", :id)

    {:error, :id, :uuid, _msg1} = assert ValidationDerive.validate(:uuid, :test, :id)
    {:error, :id, :uuid, _msg2} = assert ValidationDerive.validate(:uuid, "test", :id)
  end

  test "validate(:enum, input, field)" do
    "admin" =
      assert ValidationDerive.validate({:enum, "String[admin::user::moderator]"}, "admin", :role)

    {:error, :role, :enum, _msg5} =
      assert ValidationDerive.validate(
               {:enum, "String[admin::user::moderator]"},
               "none_role",
               :role
             )

    1 = assert ValidationDerive.validate({:enum, "Integer[1::2::3]"}, 1, :role)

    {:error, :role, :enum, _msg4} =
      assert ValidationDerive.validate({:enum, "Integer[1::2::3]"}, 99, :role)

    :user =
      assert ValidationDerive.validate({:enum, "Atom[admin::user::moderator]"}, :user, :role)

    {:error, :role, :enum, _msg3} =
      assert ValidationDerive.validate({:enum, "Atom[admin::user::moderator]"}, :banned, :role)

    {1, :admin} =
      assert ValidationDerive.validate(
               {:enum, "Tuple[{1,:admin}::{2, :user}::{3, :moderator}]"},
               {1, :admin},
               :role
             )

    {:error, :role, :enum, _msg2} =
      assert ValidationDerive.validate(
               {:enum, "Tuple[{1,:admin}::{2, :user}::{3, :moderator}]"},
               {9, :admin},
               :role
             )

    %{id: 3, role: :moderator} =
      assert ValidationDerive.validate(
               {:enum,
                "Map[%{id: 1,role: :admin}::%{id: 2, role: :user}::%{id: 3, role: :moderator}]"},
               %{id: 3, role: :moderator},
               :role
             )

    {:error, :role, :enum, _msg1} =
      assert ValidationDerive.validate(
               {:enum,
                "Map[%{id: 1,role: :admin}::%{id: 2, role: :user}::%{id: 3, role: :moderator}]"},
               %{id: 5, role: :moderator},
               :role
             )

    3.5 = assert ValidationDerive.validate({:enum, "Float[1.5::2.2::3.5]"}, 3.5, :role)

    {:error, :role, :enum, _msg} =
      assert ValidationDerive.validate({:enum, "Float[1.5::2.2::3.5]"}, 5.5, :role)
  end

  test "validate(:ipv4, input, field)" do
    valid_ip = [
      "192.168.0.1",
      "10.0.0.1",
      "172.16.0.1",
      "192.168.1.255",
      "127.0.0.1",
      "255.255.255.255",
      "8.8.8.8",
      "198.51.100.5",
      "203.0.113.12",
      "100.64.0.1",
      "172.31.255.255",
      "169.254.1.1",
      "192.0.2.1",
      "176.16.0.1",
      "185.25.144.10",
      "20.30.40.50",
      "211.144.45.67",
      "112.42.35.68",
      "132.99.0.55",
      "223.0.0.1",
      "239.255.255.255",
      "240.0.0.0",
      "249.1.2.3",
      "190.201.202.203",
      "203.200.190.180",
      "11.22.33.44",
      "100.200.150.250",
      "150.100.50.200",
      "192.168.10.20",
      "99.99.99.99",
      "46.38.29.59",
      "172.29.150.255",
      "12.34.56.78",
      "88.77.66.55",
      "190.200.210.220",
      "5.10.15.20",
      "67.89.101.121",
      "192.160.170.180",
      "208.67.222.222",
      "130.45.67.89",
      "13.14.15.16",
      "87.65.43.21",
      "16.17.18.19",
      "200.201.202.203",
      "100.101.102.103",
      "77.88.99.100",
      "111.112.113.114",
      "135.136.137.138",
      "89.90.91.92",
      "201.202.203.204"
    ]

    validated_ips =
      Enum.map(valid_ip, fn item ->
        ValidationDerive.validate(:ipv4, item, :test)
        |> case do
          value when is_tuple(value) -> false
          value when is_binary(value) -> true
        end
      end)

    true = assert Enum.all?(validated_ips)

    invalid_ipv4_list = [
      "256.0.0.1",
      "300.200.100.50",
      "192.168.256.1",
      "1.2.3.4.5",
      "500.500.500.500",
      "192.168.0.",
      "192.168.0.256",
      "192.168.0.-1",
      "127.0.0.0.1",
      "256.256.256.256",
      "invalid",
      "300.0.0.0",
      "192.168.0.0.0",
      "192.168.0",
      "192.168.0.300",
      "2001:db8::ff00:42:8329",
      "2001:0db8:0000:0042:0000:8a2e:0370:7334",
      "::1",
      "::ffff:192.168.0.1",
      "2001:0db8:85a3:0000:0000:8a2e:0370:7334",
      "fe80::1ff:fe23:4567:890a",
      "fe80::1ff:fe23:4567:890a%eth0",
      "fe80:::890a",
      "fe80:1ff:fe23:4567:890a",
      "fe80:1ff:fe23:4567:890a%",
      "fe80::1ff:fe23:4567:890a%",
      "fe80::1ff:fe23:4567:890a%1",
      "fe80::1ff:fe23:4567:890a%eth0%1",
      "fe80::1ff:fe23:4567:890a%123",
      "fe80::1ff:fe23:4567:890a%eth0%123",
      "2001:0db8:0000:0042:0000:8a2e:0370:7334%eth0",
      "2001:0db8:0000:0042:0000:8a2e:0370:7334%invalid",
      "2001:0db8:0000:0042:0000:8a2e:0370:7334%eth0%invalid",
      "fe80::1ff:fe23:4567:890a%eth0%1",
      "2001:0db8:0000:0042:0000:8a2e:0370:7334:5678",
      "2001:0db8:0000:0042:0000:8a2e:0370:7334%",
      "2001:0db8:0000:0042:0000:8a2e:0370:7334%%1",
      "2001:0db8:0000:0042:0000:8a2e:0370:7334%%eth0",
      "2001:0db8:0000:0042:0000:8a2e:0370:7334%1%",
      "fe80::1ff:fe23:4567:890a%eth0%%1",
      "fe80::1ff:fe23:4567:890a%eth0%1%",
      "fe80::1ff:fe23:4567:890a%eth0%123%",
      "192.168.0.1.",
      ".192.168.0.1",
      "192.168.0.1..",
      "192.168.0.1...",
      "192.168.0.",
      ".192.168.0.",
      "192.168.",
      ".192.168."
    ]

    invalidated_ips =
      Enum.map(invalid_ipv4_list, fn item ->
        ValidationDerive.validate(:ipv4, item, :test)
        |> case do
          value when is_tuple(value) -> false
          value when is_binary(value) -> true
        end
      end)
      |> Enum.all?()

    true = assert !invalidated_ips
  end

  test "validate(:equal, input, field)" do
    "name" = assert ValidationDerive.validate({:equal, "String::name"}, "name", :test)
    :name = assert ValidationDerive.validate({:equal, "Atom::name"}, :name, :test)
    1 = assert ValidationDerive.validate({:equal, "Integer::1"}, 1, :test)
    1.5 = assert ValidationDerive.validate({:equal, "Float::1.5"}, 1.5, :test)

    {:error, :test, :equal, _msg1} =
      assert ValidationDerive.validate({:equal, "Float::1.5"}, 1.6, :test)

    {:error, :test, :equal, _msg2} =
      assert ValidationDerive.validate({:equal, "Atom::name"}, :family, :test)

    {:error, :test, :equal, _msg3} =
      assert ValidationDerive.validate({:equal, "Float::1.5"}, "test", :test)

    %{name: "mishka"} =
      assert ValidationDerive.validate(
               {:equal, "Map::%{name: \"mishka\"}"},
               %{name: "mishka"},
               :test
             )

    {"mishka"} =
      assert ValidationDerive.validate({:equal, "Tuple::{\"mishka\"}"}, {"mishka"}, :test)
  end

  test "validate(:not_exist, input, field)" do
    {:error, :title, :type, "Unexpected type error in title field"} =
      assert ValidationDerive.validate(:not_exist, "Mishka", :title)
  end

  defmodule TestValidate do
    def validate(:testv1, input, field) do
      if is_binary(input),
        do: input,
        else: {:error, field, :testv1, "The #{field} field must not be empty"}
    end
  end

  defmodule TestValidate2 do
    def validate(:testv2, input, field) do
      if is_binary(input),
        do: input,
        else: {:error, field, :testv1, "The #{field} field must not be empty"}
    end
  end

  defmodule TestSanitize do
    def sanitize(input, :capitalize_v1) do
      if is_binary(input), do: String.capitalize(input), else: input
    end
  end

  defmodule TestSanitize2 do
    def sanitize(input, :capitalize_v2) do
      if is_binary(input), do: String.capitalize(input), else: input
    end
  end

  defmodule TestExistCustomValidateDerive do
    use GuardedStruct

    guardedstruct do
      field(:id, integer(), derives: "validate(not_exist)")
      field(:title, String.t(), derives: "validate(string)")
      field(:name, String.t(), derives: "sanitize(capitalize_v2)")
    end
  end

  defmodule TestCustomeDerive do
    use GuardedStruct

    guardedstruct do
      field(:id, integer())
      field(:title, String.t(), derives: "validate(not_empty, testv1)")
      field(:name, String.t(), derives: "validate(string, not_empty) sanitize(trim, capitalize)")
      field(:last_name, String.t(), derives: "sanitize(capitalize_v1")
      field(:nikname, String.t(), derives: "sanitize(not_exist")
    end
  end

  test "validate(:not_exist, input, field) in custom validate" do
    {:error, [%{message: "Unexpected type error in id field", field: :id, action: :type}]} =
      assert TestExistCustomValidateDerive.builder(%{id: 1, title: "Mishka"})
  end

  test "validate(:custom_validate_derive, input, field) in custom validate" do
    {:ok,
     %__MODULE__.TestCustomeDerive{
       title: "Mishka",
       id: 1,
       name: "Shahryar",
       last_name: "Tavakkoli",
       nikname: "test"
     }} =
      assert TestCustomeDerive.builder(%{
               id: 1,
               title: "Mishka",
               name: " shahryar ",
               last_name: "tavakkoli",
               nikname: "test"
             })

    {:error,
     [
       %{message: "The title field must not be empty", field: :title, action: :testv1},
       %{
         message:
           "Invalid NotEmpty format in the title field, you must pass data which is string, list or map.",
         field: :title,
         action: :not_empty
       }
     ]} = assert TestCustomeDerive.builder(%{id: 1, title: 1})
  end

  Application.put_env(:guarded_struct, :validate_derive, [TestValidate, TestValidate2])
  Application.put_env(:guarded_struct, :sanitize_derive, [TestSanitize, TestSanitize2])

  defmodule TestCustomListDerive do
    use GuardedStruct

    guardedstruct do
      field(:id, integer())
      field(:title, String.t(), derives: "validate(not_empty, testv2)")

      field(:name, String.t(),
        derives: "validate(string, not_empty) sanitize(trim, capitalize_v2)"
      )

      field(:last_name, String.t(), derives: "sanitize(capitalize_v1")
      field(:nikname, String.t(), derives: "sanitize(not_exist")
    end
  end

  test "test custom validate and sanitize list derive" do
    {:ok,
     %__MODULE__.TestCustomListDerive{
       title: "Mishka",
       id: 1,
       name: "Shahryar",
       last_name: "Tavakkoli",
       nikname: "test"
     }} =
      assert TestCustomListDerive.builder(%{
               id: 1,
               title: "Mishka",
               name: " shahryar ",
               last_name: "tavakkoli",
               nikname: "test"
             })
  end

  defmodule TestEitherValidationDerive do
    use GuardedStruct

    guardedstruct do
      field(:test, String.t(), derives: "validate(either=[integer, max_len=4])")
      field(:test1, String.t(), derives: "validate(either=[string, enum=Integer[1::2::3]])")
    end
  end

  test "validate(:either, input, field)" do
    {:ok,
     %__MODULE__.TestEitherValidationDerive{
       test: 12
     }} = assert TestEitherValidationDerive.builder(%{test: 12})

    {:error,
     [
       %{
         message: _msg,
         field: :test,
         action: :either
       }
     ]} = assert TestEitherValidationDerive.builder(%{test: "mishka"})

    {:ok,
     %__MODULE__.TestEitherValidationDerive{
       test1: 3,
       test: nil
     }} = assert TestEitherValidationDerive.builder(%{test1: 3})
  end

  defmodule TestCustomValidationDerive do
    use GuardedStruct

    guardedstruct authorized_fields: true do
      field(:status, String.t(), derives: "validate(custom=[#{__MODULE__}, is_stuff?])")
    end

    def is_stuff?(data) when data == "ok", do: true
    def is_stuff?(_data), do: false
  end

  test "validate({:custom, value}, input, field)" do
    {:ok,
     %__MODULE__.TestCustomValidationDerive{
       status: "ok"
     }} = assert TestCustomValidationDerive.builder(%{status: "ok"})

    {:error,
     [
       %{
         message: "The condition for checking the status field is not correct",
         field: :status,
         action: :custom
       }
     ]} =
      assert TestCustomValidationDerive.builder(%{status: "error"})
  end

  test "validate(:string_float, input, field)" do
    {:error, _, :string_float, _} = assert ValidationDerive.validate(:string_float, "name", :test)
    {:error, _, :string_float, _} = assert ValidationDerive.validate(:string_float, "0", :test)

    {:error, _, :string_float, _} =
      assert ValidationDerive.validate(:string_float, "3.5sss", :test)

    "3.5" = assert ValidationDerive.validate(:string_float, "3.5", :test)
    {:error, _, :string_float, _} = assert ValidationDerive.validate(:string_float, 3.5, :test)
  end

  test "validate(:some_string_float, input, field)" do
    {:error, _, :some_string_float, _} =
      assert ValidationDerive.validate(:some_string_float, "name", :test)

    "3.5" = assert ValidationDerive.validate(:some_string_float, "3.5", :test)
    "3.5sss" = assert ValidationDerive.validate(:some_string_float, "3.5sss", :test)

    "0" = assert ValidationDerive.validate(:some_string_float, "0", :test)
  end

  test "validate(:string_integer, input, field)" do
    {:error, _, :string_integer, _} =
      assert ValidationDerive.validate(:string_integer, "name", :test)

    "0" = assert ValidationDerive.validate(:string_integer, "0", :test)

    {:error, _, :string_integer, _} =
      assert ValidationDerive.validate(:string_integer, "3.5sss", :test)

    {:error, _, :string_integer, _} =
      assert ValidationDerive.validate(:string_integer, "3.5", :test)

    {:error, _, :string_integer, _} =
      assert ValidationDerive.validate(:string_integer, 3.5, :test)
  end

  test "validate(:some_string_integer, input, field)" do
    {:error, _, :some_string_integer, _} =
      assert ValidationDerive.validate(:some_string_integer, "name", :test)

    "3.5" = assert ValidationDerive.validate(:some_string_integer, "3.5", :test)
    "3.5sss" = assert ValidationDerive.validate(:some_string_integer, "3.5sss", :test)

    "0" = assert ValidationDerive.validate(:some_string_integer, "0", :test)
  end

  describe "list hygiene sanitizers" do
    test ":uniq removes duplicates while preserving order" do
      assert SanitizerDerive.sanitize([1, 2, 2, 3, 1], :uniq) == [1, 2, 3]
    end

    test ":uniq passes non-list through" do
      assert SanitizerDerive.sanitize("hi", :uniq) == "hi"
    end

    test ":compact drops nils" do
      assert SanitizerDerive.sanitize([1, nil, 2, nil], :compact) == [1, 2]
    end

    test ":reject_empty drops nil, empty string, empty list, empty map" do
      assert SanitizerDerive.sanitize([1, "", nil, [], %{}, "ok"], :reject_empty) == [1, "ok"]
    end

    test ":sort sorts a list of comparables" do
      assert SanitizerDerive.sanitize([3, 1, 2], :sort) == [1, 2, 3]
    end
  end

  describe "string hygiene sanitizers" do
    test ":squish collapses runs of whitespace and trims" do
      assert SanitizerDerive.sanitize("  hello   world  ", :squish) == "hello world"
    end

    test ":no_control strips ASCII control characters" do
      assert SanitizerDerive.sanitize("hi\x00there\x1F!", :no_control) == "hithere!"
    end

    test ":no_zero_width strips zero-width unicode chars" do
      assert SanitizerDerive.sanitize("hi​there", :no_zero_width) == "hithere"
    end

    test "string-hygiene ops passthrough on non-binary" do
      assert SanitizerDerive.sanitize(123, :squish) == 123
      assert SanitizerDerive.sanitize(nil, :no_control) == nil
    end
  end

  describe ":rich_text_safe — composed string hygiene" do
    test "strips zero-width unicode characters" do
      assert SanitizerDerive.sanitize("hi​there‌!", :rich_text_safe) == "hithere!"
    end

    test "strips ASCII control bytes" do
      assert SanitizerDerive.sanitize("hi\x00there\x1F!", :rich_text_safe) == "hithere!"
    end

    test "strips both zero-width and control characters in a single pass" do
      mixed = "a​b\x00c‌d\x1Fe"
      assert SanitizerDerive.sanitize(mixed, :rich_text_safe) == "abcde"
    end

    test "preserves regular whitespace (tab, newline, carriage return, space)" do
      assert SanitizerDerive.sanitize("line1\nline2\tcol\r\nend", :rich_text_safe) ==
               "line1\nline2\tcol\r\nend"
    end

    test "is equivalent to chaining :no_zero_width and :no_control" do
      input = "x​y\x00z‌w\x1F"

      chained =
        input
        |> SanitizerDerive.sanitize(:no_zero_width)
        |> SanitizerDerive.sanitize(:no_control)

      assert SanitizerDerive.sanitize(input, :rich_text_safe) == chained
    end

    test "leaves clean text unchanged" do
      assert SanitizerDerive.sanitize("hello world", :rich_text_safe) == "hello world"
    end

    test "returns empty string unchanged" do
      assert SanitizerDerive.sanitize("", :rich_text_safe) == ""
    end

    test "passes through non-binary inputs untouched" do
      assert SanitizerDerive.sanitize(nil, :rich_text_safe) == nil
      assert SanitizerDerive.sanitize(123, :rich_text_safe) == 123
      assert SanitizerDerive.sanitize(:atom, :rich_text_safe) == :atom
      assert SanitizerDerive.sanitize([1, 2], :rich_text_safe) == [1, 2]
      assert SanitizerDerive.sanitize(%{a: 1}, :rich_text_safe) == %{a: 1}
    end

    test "call/2 reduces a single :rich_text_safe action over a field" do
      assert {:bio, "clean"} =
               SanitizerDerive.call({:bio, "cl​e\x00an"}, [:rich_text_safe])
    end
  end

  describe "clamp sanitizer" do
    test "clamps below min" do
      assert SanitizerDerive.sanitize(-5, {:clamp, [0, 100]}) == 0
    end

    test "clamps above max" do
      assert SanitizerDerive.sanitize(200, {:clamp, [0, 100]}) == 100
    end

    test "leaves in-range untouched" do
      assert SanitizerDerive.sanitize(50, {:clamp, [0, 100]}) == 50
    end

    test "works on floats" do
      assert SanitizerDerive.sanitize(1.5, {:clamp, [0.0, 1.0]}) == 1.0
    end

    test "passthrough on non-number" do
      assert SanitizerDerive.sanitize("hi", {:clamp, [0, 100]}) == "hi"
    end
  end

  describe "default-fill sanitizers" do
    test ":default_when_nil replaces nil" do
      assert SanitizerDerive.sanitize(nil, {:default_when_nil, 42}) == 42
    end

    test ":default_when_nil leaves non-nil alone" do
      assert SanitizerDerive.sanitize(7, {:default_when_nil, 42}) == 7
    end

    test ":default_when_empty handles nil, empty string, empty list, empty map" do
      assert SanitizerDerive.sanitize(nil, {:default_when_empty, :x}) == :x
      assert SanitizerDerive.sanitize("", {:default_when_empty, :x}) == :x
      assert SanitizerDerive.sanitize([], {:default_when_empty, :x}) == :x
      assert SanitizerDerive.sanitize(%{}, {:default_when_empty, :x}) == :x
    end

    test ":default_when_empty leaves non-empty alone" do
      assert SanitizerDerive.sanitize("hi", {:default_when_empty, :x}) == "hi"
      assert SanitizerDerive.sanitize([1], {:default_when_empty, :x}) == [1]
    end
  end

  describe "named regex aliases" do
    test ":slug accepts kebab-case lowercase" do
      assert ValidationDerive.validate(:slug, "my-slug-1", :name) == "my-slug-1"
    end

    test ":slug rejects uppercase, underscores, leading/trailing dashes" do
      assert {:error, :name, :slug, _} = ValidationDerive.validate(:slug, "MySlug", :name)
      assert {:error, :name, :slug, _} = ValidationDerive.validate(:slug, "my_slug", :name)
      assert {:error, :name, :slug, _} = ValidationDerive.validate(:slug, "-foo", :name)
      assert {:error, :name, :slug, _} = ValidationDerive.validate(:slug, "foo-", :name)
    end

    test ":hostname accepts simple + subdomain forms" do
      assert ValidationDerive.validate(:hostname, "example.com", :host) == "example.com"
      assert ValidationDerive.validate(:hostname, "a.b.example.com", :host) == "a.b.example.com"
    end

    test ":hostname rejects underscore, scheme, length > 253" do
      assert {:error, :host, :hostname, _} =
               ValidationDerive.validate(:hostname, "bad_host.io", :host)

      assert {:error, :host, :hostname, _} =
               ValidationDerive.validate(:hostname, "https://example.com", :host)

      long = String.duplicate("a", 254)

      assert {:error, :host, :hostname, _} =
               ValidationDerive.validate(:hostname, long, :host)
    end

    test ":port_number accepts 1..65535 integers" do
      assert ValidationDerive.validate(:port_number, 1, :port) == 1
      assert ValidationDerive.validate(:port_number, 65535, :port) == 65535
      assert ValidationDerive.validate(:port_number, 8080, :port) == 8080
    end

    test ":port_number rejects out-of-range and non-integer" do
      assert {:error, :port, :port_number, _} =
               ValidationDerive.validate(:port_number, 0, :port)

      assert {:error, :port, :port_number, _} =
               ValidationDerive.validate(:port_number, 70000, :port)

      assert {:error, :port, :port_number, _} =
               ValidationDerive.validate(:port_number, "80", :port)
    end

    test ":hex_color accepts #RRGGBB and #RGB" do
      assert ValidationDerive.validate(:hex_color, "#FF00aa", :color) == "#FF00aa"
      assert ValidationDerive.validate(:hex_color, "#abc", :color) == "#abc"
    end

    test ":hex_color rejects missing hash, wrong length, bad chars" do
      assert {:error, :color, :hex_color, _} =
               ValidationDerive.validate(:hex_color, "FF0000", :color)

      assert {:error, :color, :hex_color, _} =
               ValidationDerive.validate(:hex_color, "#FF00", :color)

      assert {:error, :color, :hex_color, _} =
               ValidationDerive.validate(:hex_color, "#GG0000", :color)
    end

    test ":semver accepts basic + prerelease + build forms" do
      assert ValidationDerive.validate(:semver, "1.2.3", :version) == "1.2.3"
      assert ValidationDerive.validate(:semver, "1.0.0-alpha.1", :version) == "1.0.0-alpha.1"
      assert ValidationDerive.validate(:semver, "1.0.0+build.42", :version) == "1.0.0+build.42"
    end

    test ":semver rejects malformed versions" do
      assert {:error, :version, :semver, _} =
               ValidationDerive.validate(:semver, "v1.2.3", :version)

      assert {:error, :version, :semver, _} =
               ValidationDerive.validate(:semver, "1.2", :version)

      assert {:error, :version, :semver, _} =
               ValidationDerive.validate(:semver, "1.2.3.4", :version)
    end
  end

  describe "optional wrapper" do
    test "nil passes through unchanged regardless of inner ops" do
      assert nil == ValidationDerive.validate({:optional, [:string]}, nil, :f)
      assert nil == ValidationDerive.validate({:optional, "string"}, nil, :f)
      assert nil == ValidationDerive.validate({:optional, :string}, nil, :f)
      assert nil == ValidationDerive.validate(%{optional: [:string, {:max_len, 5}]}, nil, :f)
    end

    test "non-nil value runs inner ops" do
      assert "ok" == ValidationDerive.validate({:optional, [:string]}, "ok", :f)
      assert "ok" == ValidationDerive.validate(%{optional: [:string, {:max_len, 5}]}, "ok", :f)
    end

    test "non-nil value fails when inner op rejects" do
      assert {:error, :f, :string, _} =
               ValidationDerive.validate({:optional, [:string]}, 42, :f)

      assert {:error, :f, :max_len, _} =
               ValidationDerive.validate(%{optional: [:string, {:max_len, 2}]}, "long", :f)
    end
  end

  describe "each combinator — sanitize" do
    test "applies inner sanitize ops to every element of a list" do
      assert ["a", "b"] ==
               SanitizerDerive.sanitize(["  A  ", "  B  "], %{each: [:trim, :downcase]})
    end

    test "tuple form (atoms-only inner list) also works" do
      assert ["a", "b"] ==
               SanitizerDerive.sanitize(["  A  ", "  B  "], {:each, [:trim, :downcase]})
    end

    test "passthrough on non-list input" do
      assert "hi" == SanitizerDerive.sanitize("hi", %{each: [:downcase]})
    end

    test "empty list stays empty" do
      assert [] == SanitizerDerive.sanitize([], %{each: [:trim]})
    end
  end

  describe "each combinator — validate" do
    test "every element passes inner ops → input returned unchanged" do
      assert ["a", "b"] == ValidationDerive.validate(%{each: [:string]}, ["a", "b"], :tags)
    end

    test "any failing element returns 5-tuple with structured per-index children" do
      result = ValidationDerive.validate(%{each: [:string]}, ["a", 2, "c", 4], :tags)

      assert {:error, :tags, :each, "One or more items in the tags field failed validation",
              {:children,
               [
                 %{
                   field: :tags,
                   action: :string,
                   __index__: 1,
                   message: "The tags field must be string"
                 },
                 %{
                   field: :tags,
                   action: :string,
                   __index__: 3,
                   message: "The tags field must be string"
                 }
               ]}} = result
    end

    test "multiple failing ops per element produce one child per (index, op)" do
      assert {:error, :tags, :each, _, {:children, children}} =
               ValidationDerive.validate(%{each: [:string, :not_empty]}, ["", 2], :tags)

      actions_by_index = Enum.group_by(children, & &1.__index__, & &1.action)
      assert :not_empty in actions_by_index[0]
      assert :string in actions_by_index[1]
    end

    test "non-list input gets the generic :each error" do
      assert {:error, :tags, :each, _} =
               ValidationDerive.validate(%{each: [:string]}, "not-a-list", :tags)
    end

    test "tuple form (atoms-only inner list) also works" do
      assert ["a"] == ValidationDerive.validate({:each, [:string]}, ["a"], :tags)
    end

    test "call/3 flattens the children into the returned errors list" do
      {_first, errors} =
        ValidationDerive.call({:tags, ["a", 2, "c", 4]}, [%{each: [:string]}], [])

      assert [
               %{
                 field: :tags,
                 action: :string,
                 __index__: 1,
                 message: "The tags field must be string"
               },
               %{
                 field: :tags,
                 action: :string,
                 __index__: 3,
                 message: "The tags field must be string"
               }
             ] = errors
    end

    test "call/3 propagates hint onto every child error" do
      {_first, errors} =
        ValidationDerive.call({:tags, ["a", 2]}, [%{each: [:string]}], "form-row")

      assert Enum.all?(errors, &(Map.get(&1, :__hint__) == "form-row"))
    end
  end

  describe "datetime / date / time shape validators" do
    test ":utc_datetime accepts %DateTime{} and ISO-8601 binary, rejects anything else" do
      now = DateTime.utc_now()
      assert ^now = ValidationDerive.validate(:utc_datetime, now, :ts)

      assert "2026-05-22T12:00:00Z" =
               ValidationDerive.validate(:utc_datetime, "2026-05-22T12:00:00Z", :ts)

      assert {:error, :ts, :utc_datetime, _} =
               ValidationDerive.validate(:utc_datetime, "not-iso", :ts)

      assert {:error, :ts, :utc_datetime, _} = ValidationDerive.validate(:utc_datetime, 123, :ts)
    end

    test ":naive_datetime accepts %NaiveDateTime{} and ISO-8601 binary" do
      naive = ~N[2026-05-22 12:00:00]
      assert ^naive = ValidationDerive.validate(:naive_datetime, naive, :ts)

      assert "2026-05-22T12:00:00" =
               ValidationDerive.validate(:naive_datetime, "2026-05-22T12:00:00", :ts)

      assert {:error, :ts, :naive_datetime, _} =
               ValidationDerive.validate(:naive_datetime, "nope", :ts)
    end

    test ":date_struct accepts %Date{} and ISO-8601 date binary" do
      today = ~D[2026-05-22]
      assert ^today = ValidationDerive.validate(:date_struct, today, :d)

      assert "2026-05-22" = ValidationDerive.validate(:date_struct, "2026-05-22", :d)

      assert {:error, :d, :date_struct, _} = ValidationDerive.validate(:date_struct, "x", :d)
    end

    test ":time_struct accepts %Time{} and ISO-8601 time binary" do
      now = ~T[12:00:00]
      assert ^now = ValidationDerive.validate(:time_struct, now, :t)

      assert "12:00:00" = ValidationDerive.validate(:time_struct, "12:00:00", :t)

      assert {:error, :t, :time_struct, _} = ValidationDerive.validate(:time_struct, "noon", :t)
    end
  end

  describe ":past_datetime and :future_datetime" do
    test ":past_datetime accepts past %DateTime{}, current instant, rejects future" do
      past = DateTime.add(DateTime.utc_now(), -3600, :second)
      assert ^past = ValidationDerive.validate(:past_datetime, past, :applied_at)

      # "Now" passes because by the time the validator runs, `utc_now()` is a
      # few microseconds later — submitted is already past-or-equal.
      now = DateTime.utc_now()
      assert ^now = ValidationDerive.validate(:past_datetime, now, :applied_at)

      future = DateTime.add(DateTime.utc_now(), 3600, :second)

      assert {:error, :applied_at, :past_datetime, _} =
               ValidationDerive.validate(:past_datetime, future, :applied_at)
    end

    test ":future_datetime accepts future %DateTime{}, current instant, rejects past" do
      future = DateTime.add(DateTime.utc_now(), 3600, :second)

      assert ^future =
               ValidationDerive.validate(:future_datetime, future, :scheduled_at)

      past = DateTime.add(DateTime.utc_now(), -3600, :second)

      assert {:error, :scheduled_at, :future_datetime, _} =
               ValidationDerive.validate(:future_datetime, past, :scheduled_at)
    end

    test ":past_datetime also accepts %NaiveDateTime{} and %Date{}" do
      past_naive = NaiveDateTime.add(NaiveDateTime.utc_now(), -3600, :second)
      assert ^past_naive = ValidationDerive.validate(:past_datetime, past_naive, :ts)

      yesterday = Date.add(Date.utc_today(), -1)
      assert ^yesterday = ValidationDerive.validate(:past_datetime, yesterday, :d)
    end

    test ":future_datetime also accepts %NaiveDateTime{} and %Date{}" do
      future_naive = NaiveDateTime.add(NaiveDateTime.utc_now(), 3600, :second)
      assert ^future_naive = ValidationDerive.validate(:future_datetime, future_naive, :ts)

      tomorrow = Date.add(Date.utc_today(), 1)
      assert ^tomorrow = ValidationDerive.validate(:future_datetime, tomorrow, :d)
    end

    test "both accept ISO-8601 binaries and apply the same past/future rule" do
      past_iso = DateTime.add(DateTime.utc_now(), -3600, :second) |> DateTime.to_iso8601()
      future_iso = DateTime.add(DateTime.utc_now(), 3600, :second) |> DateTime.to_iso8601()

      assert ^past_iso = ValidationDerive.validate(:past_datetime, past_iso, :ts)
      assert ^future_iso = ValidationDerive.validate(:future_datetime, future_iso, :ts)

      assert {:error, :ts, :past_datetime, _} =
               ValidationDerive.validate(:past_datetime, future_iso, :ts)

      assert {:error, :ts, :future_datetime, _} =
               ValidationDerive.validate(:future_datetime, past_iso, :ts)
    end

    test "both reject non-temporal inputs with explicit error" do
      assert {:error, :x, :past_datetime, _} =
               ValidationDerive.validate(:past_datetime, 123, :x)

      assert {:error, :x, :future_datetime, _} =
               ValidationDerive.validate(:future_datetime, nil, :x)

      assert {:error, :x, :past_datetime, _} =
               ValidationDerive.validate(:past_datetime, "not-iso", :x)
    end
  end

  describe "dispatch-order regression — every registered op has a dedicated clause" do
    # If a developer ever inserts a defp between two def validate/3 clauses,
    # the Elixir compiler warns ("clauses with the same name and arity should
    # be grouped together"). With `mix test --warnings-as-errors` that becomes
    # a failure, but plain runs only show a warning. This test catches the
    # subtler symptom: a clause physically placed AFTER the catchall is dead,
    # because the catchall matches first. We probe every op in the registry
    # with a deliberately-wrong-shape value and assert the error action is
    # the op's own atom — not the catchall's `:type` action.

    test "every validate-op atom has a clause that fires before the catchall" do
      # Pair every bare-atom op with an input it MUST reject. If the dedicated
      # clause is missing or placed after the catchall, the catchall fires
      # with action `:type` instead of the op's own action, and we catch it.
      probes = [
        {:string, 42},
        {:integer, "x"},
        {:float, 1},
        {:number, "x"},
        {:list, "x"},
        {:map, "x"},
        {:tuple, "x"},
        {:atom, "x"},
        {:bitstring, 1},
        {:boolean, "x"},
        {:struct, "x"},
        {:nil_value, 1},
        {:not_nil_value, nil},
        {:not_empty, ""},
        {:not_flatten_empty, []},
        {:not_flatten_empty_item, [[], []]},
        {:queue, "x"},
        {:not_empty_string, ""},
        {:uuid, "not-a-uuid"},
        {:ipv4, "999.999.999.999"},
        {:ipv6, "not-an-ipv6"},
        {:ip, "not-an-ip"},
        {:language_code, "english"},
        {:datetime, "not-iso"},
        {:date, "not-iso"},
        {:range, "x"},
        {:email_r, "not-email"},
        {:username, ""},
        {:full_name, 123},
        {:string_boolean, "maybe"},
        {:string_float, "abc"},
        {:string_integer, "abc"},
        {:some_string_float, "abc"},
        {:some_string_integer, "abc"},
        {:record, "x"},
        {:slug, "Has Spaces"},
        {:hostname, "bad_host_with_underscore"},
        {:port_number, 70_000},
        {:hex_color, "not-a-color"},
        {:semver, "v1.0"},
        {:past_datetime, "not-iso"},
        {:future_datetime, "not-iso"},
        {:utc_datetime, "not-iso"},
        {:naive_datetime, "not-iso"},
        {:date_struct, "not-iso"},
        {:time_struct, "not-iso"}
      ]

      for {op, bad_input} <- probes do
        result = ValidationDerive.validate(op, bad_input, :probe)

        assert {:error, :probe, action, _msg} = result,
               "op #{inspect(op)} did not reject #{inspect(bad_input)}: got #{inspect(result)}"

        refute action == :type,
               "op #{inspect(op)} fell through to the catchall (action: :type). " <>
                 "Its dedicated clause may have been deleted, shadowed, or placed " <>
                 "after `def validate(action, input, field)`."
      end
    end

    test "ipv6 + ip — accept/reject contract is pure (no network)" do
      # IPv6 happy path — full and abbreviated forms
      assert "2001:db8::1" = ValidationDerive.validate(:ipv6, "2001:db8::1", :ip)
      assert "::1" = ValidationDerive.validate(:ipv6, "::1", :ip)

      assert "2001:0db8:85a3:0000:0000:8a2e:0370:7334" =
               ValidationDerive.validate(
                 :ipv6,
                 "2001:0db8:85a3:0000:0000:8a2e:0370:7334",
                 :ip
               )

      # IPv6 rejects v4 + garbage
      assert {:error, :ip, :ipv6, _} = ValidationDerive.validate(:ipv6, "192.168.0.1", :ip)
      assert {:error, :ip, :ipv6, _} = ValidationDerive.validate(:ipv6, "gibberish", :ip)
      assert {:error, :ip, :ipv6, _} = ValidationDerive.validate(:ipv6, "", :ip)
      assert {:error, :ip, :ipv6, _} = ValidationDerive.validate(:ipv6, 42, :ip)

      # :ip — either v4 or v6
      assert "127.0.0.1" = ValidationDerive.validate(:ip, "127.0.0.1", :ip)
      assert "::1" = ValidationDerive.validate(:ip, "::1", :ip)
      assert "2001:db8::1" = ValidationDerive.validate(:ip, "2001:db8::1", :ip)

      assert {:error, :ip, :ip, _} = ValidationDerive.validate(:ip, "not-an-ip", :ip)
      assert {:error, :ip, :ip, _} = ValidationDerive.validate(:ip, "999.999.999.999", :ip)
      assert {:error, :ip, :ip, _} = ValidationDerive.validate(:ip, nil, :ip)
    end

    test "no clause was placed AFTER the catchall (would be dead code)" do
      # The catchall is `def validate(action, input, field)` with no pattern.
      # Any subsequent `def validate/3` clause would be unreachable. We can't
      # introspect the AST cheaply, so we proxy: probe with an unknown atom
      # that no registered op uses and assert it hits the catchall.

      unknown_op = :__no_such_op_should_ever_exist__
      result = ValidationDerive.validate(unknown_op, "anything", :probe)

      # The catchall delegates to Extension.dispatch_validate which falls
      # through to fallback_dispatch returning the generic :type error.
      assert {:error, :probe, :type, _} = result
    end
  end

  describe "comprehensive edge cases — sanitize ops" do
    test "clamp on negative floats, identical-bound, and exact boundaries" do
      # Exact-equal bound passes (inclusive)
      assert 0 == SanitizerDerive.sanitize(0, {:clamp, [0, 100]})
      assert 100 == SanitizerDerive.sanitize(100, {:clamp, [0, 100]})

      # Negative range, negative input
      assert -10 == SanitizerDerive.sanitize(-20, {:clamp, [-10, -1]})
      assert -1 == SanitizerDerive.sanitize(0, {:clamp, [-10, -1]})

      # Single-point range
      assert 5 == SanitizerDerive.sanitize(0, {:clamp, [5, 5]})
      assert 5 == SanitizerDerive.sanitize(10, {:clamp, [5, 5]})
      assert 5 == SanitizerDerive.sanitize(5, {:clamp, [5, 5]})

      # Float boundaries
      assert -1.5 == SanitizerDerive.sanitize(-2.0, {:clamp, [-1.5, 1.5]})
      assert 1.5 == SanitizerDerive.sanitize(2.0, {:clamp, [-1.5, 1.5]})
    end

    test "default_when_empty does NOT replace whitespace-only string (only literal \"\")" do
      # Important: "   " (spaces) is NOT empty. The user must `trim` first
      # if they want spaces collapsed to nil.
      assert "   " == SanitizerDerive.sanitize("   ", {:default_when_empty, "fallback"})

      # Order matters — trim first, then default_when_empty
      "   "
      |> SanitizerDerive.sanitize(:trim)
      |> SanitizerDerive.sanitize({:default_when_empty, "fallback"})
      |> Kernel.==("fallback")
      |> assert()
    end

    test "uniq + sort + reject_empty compose in declared order" do
      input = ["b", "a", nil, "b", "", "a"]

      assert ["a", "b"] ==
               input
               |> SanitizerDerive.sanitize(:reject_empty)
               |> SanitizerDerive.sanitize(:uniq)
               |> SanitizerDerive.sanitize(:sort)
    end

    test "each sanitize composes with subsequent list-level ops" do
      input = ["  HELLO  ", "  hello  ", "  WORLD  "]

      assert ["hello", "world"] ==
               input
               |> SanitizerDerive.sanitize(%{each: [:trim, :downcase]})
               |> SanitizerDerive.sanitize(:uniq)
    end
  end

  describe "comprehensive edge cases — validate ops" do
    test ":each on empty list passes (vacuously true)" do
      assert [] == ValidationDerive.validate(%{each: [:string]}, [], :tags)
    end

    test ":each on single-element list with mixed inner ops" do
      assert ["ok"] ==
               ValidationDerive.validate(%{each: [:string, :not_empty]}, ["ok"], :tags)
    end

    test "optional wraps a parameterised inner op (max_len) end-to-end" do
      # nil short-circuits
      assert nil == ValidationDerive.validate({:optional, [:string, {:max_len, 5}]}, nil, :f)

      # Within bounds
      assert "abc" ==
               ValidationDerive.validate({:optional, [:string, {:max_len, 5}]}, "abc", :f)

      # Over bounds — surfaces the inner op's action, not :optional
      assert {:error, :f, :max_len, _} =
               ValidationDerive.validate(
                 {:optional, [:string, {:max_len, 5}]},
                 "way-too-long",
                 :f
               )
    end

    test ":past_datetime — DateTime.utc_now() at exact instant passes (inclusive eq)" do
      # Construct an instant slightly in the past so that even on the fastest
      # machine `utc_now()` is strictly >= it. Verifies the [:lt, :eq] branch.
      now = DateTime.utc_now()
      :timer.sleep(2)
      assert ^now = ValidationDerive.validate(:past_datetime, now, :ts)
    end

    test ":future_datetime — DateTime.utc_now() at exact instant passes (inclusive eq)" do
      future = DateTime.add(DateTime.utc_now(), 10, :second)
      assert ^future = ValidationDerive.validate(:future_datetime, future, :ts)
    end

    test ":past_datetime accepts ISO-8601 strings (both past and rejects future)" do
      past_iso = DateTime.add(DateTime.utc_now(), -3600, :second) |> DateTime.to_iso8601()
      future_iso = DateTime.add(DateTime.utc_now(), 3600, :second) |> DateTime.to_iso8601()

      assert ^past_iso = ValidationDerive.validate(:past_datetime, past_iso, :ts)

      assert {:error, :ts, :past_datetime, _} =
               ValidationDerive.validate(:past_datetime, future_iso, :ts)
    end

    test ":ip accepts boundary v4/v6 values" do
      for ip <- [
            # IPv4 boundaries
            "0.0.0.0",
            "255.255.255.255",
            # IPv6 special forms
            "::",
            "::1",
            "fe80::1",
            "2001:db8::ff",
            # Full IPv6 form
            "2001:0db8:85a3:0000:0000:8a2e:0370:7334"
          ] do
        assert ^ip = ValidationDerive.validate(:ip, ip, :addr)
      end
    end

    test ":ipv6 rejects v4 strings, integers, and empty strings" do
      assert {:error, :addr, :ipv6, _} = ValidationDerive.validate(:ipv6, "192.168.0.1", :addr)
      assert {:error, :addr, :ipv6, _} = ValidationDerive.validate(:ipv6, "127.0.0.1", :addr)
      assert {:error, :addr, :ipv6, _} = ValidationDerive.validate(:ipv6, "", :addr)
      assert {:error, :addr, :ipv6, _} = ValidationDerive.validate(:ipv6, "::g", :addr)
      assert {:error, :addr, :ipv6, _} = ValidationDerive.validate(:ipv6, 12345, :addr)
      assert {:error, :addr, :ipv6, _} = ValidationDerive.validate(:ipv6, nil, :addr)
    end

    test ":utc_datetime accepts both struct and binary, rejects atoms" do
      now = DateTime.utc_now()
      assert ^now = ValidationDerive.validate(:utc_datetime, now, :ts)

      iso = "2026-01-01T12:00:00Z"
      assert ^iso = ValidationDerive.validate(:utc_datetime, iso, :ts)

      assert {:error, :ts, :utc_datetime, _} =
               ValidationDerive.validate(:utc_datetime, :not_a_date, :ts)
    end

    test ":semver accepts canonical, prerelease, and build forms; rejects v-prefix" do
      for ok <- [
            "0.0.0",
            "1.0.0",
            "1.2.3",
            "1.0.0-alpha",
            "1.0.0-alpha.1",
            "1.0.0-0.3.7",
            "1.0.0-x.7.z.92",
            "1.0.0+20130313144700",
            "1.0.0-beta+exp.sha.5114f85"
          ] do
        assert ^ok = ValidationDerive.validate(:semver, ok, :v)
      end

      for bad <- ["v1.0.0", "1", "1.2", "01.0.0", "1.0.0-", "1.0.0+"] do
        assert {:error, :v, :semver, _} = ValidationDerive.validate(:semver, bad, :v),
               "expected :semver rejection for #{inspect(bad)}"
      end
    end
  end

  describe ":not_empty_string (already existed — pinned contract)" do
    # This op was already in the lib before this PR. Pinning behavior so
    # nobody accidentally tightens or loosens it.

    test "accepts any non-empty binary, regardless of contents" do
      for ok <- ["a", "hello world", "  ", "\n", "0", "false", "​"] do
        assert ^ok = ValidationDerive.validate(:not_empty_string, ok, :s)
      end
    end

    test "rejects empty binary, nil, non-binary, and non-string types" do
      for bad <- ["", nil, 0, :atom, [], %{}, 123, true] do
        assert {:error, :s, :not_empty_string, _} =
                 ValidationDerive.validate(:not_empty_string, bad, :s),
               "expected :not_empty_string rejection for #{inspect(bad)}"
      end
    end

    test "is purely a length check — does NOT trim whitespace-only input" do
      # Whitespace-only strings are NOT considered empty (they are non-empty
      # binaries). To reject them, callers should compose `sanitize(trim)`
      # first. This test guards against a well-meaning future contributor
      # adding a trim inside the validator.
      assert "   " = ValidationDerive.validate(:not_empty_string, "   ", :s)
      assert "\t" = ValidationDerive.validate(:not_empty_string, "\t", :s)
    end
  end

  describe ":language_code — BCP-47 / ISO 639-1 shape" do
    test "accepts 2-letter primary language codes" do
      for ok <- ["en", "fa", "ar", "ru", "de", "fr", "ja", "zh", "ko", "es", "pt"] do
        assert ^ok = ValidationDerive.validate(:language_code, ok, :lang)
      end
    end

    test "accepts 3-letter primary language codes" do
      # ISO 639-2/3 three-letter codes (e.g. yue Cantonese, cmn Mandarin)
      for ok <- ["yue", "cmn", "wuu", "fil", "haw"] do
        assert ^ok = ValidationDerive.validate(:language_code, ok, :lang)
      end
    end

    test "accepts language-region forms (e.g. en-US, pt-BR)" do
      for ok <- ["en-US", "en-GB", "pt-BR", "es-MX", "fr-CA", "zh-CN", "zh-TW"] do
        assert ^ok = ValidationDerive.validate(:language_code, ok, :lang)
      end
    end

    test "accepts language-script forms (e.g. zh-Hant, sr-Cyrl)" do
      for ok <- ["zh-Hant", "zh-Hans", "sr-Cyrl", "sr-Latn", "ja-Hira", "az-Arab"] do
        assert ^ok = ValidationDerive.validate(:language_code, ok, :lang)
      end
    end

    test "accepts language-script-region forms (e.g. zh-Hant-HK)" do
      for ok <- ["zh-Hant-HK", "zh-Hans-CN", "sr-Cyrl-RS", "az-Arab-IR"] do
        assert ^ok = ValidationDerive.validate(:language_code, ok, :lang)
      end
    end

    test "accepts UN M.49 region codes (3 digits)" do
      # 419 = Latin America, 029 = Caribbean, 005 = South America
      for ok <- ["es-419", "en-029", "es-005"] do
        assert ^ok = ValidationDerive.validate(:language_code, ok, :lang)
      end
    end

    test "accepts variant subtags" do
      # BCP-47 variant subtags are 5–8 alphanumeric (e.g. `1996` German
      # orthography reform, `valencia` Catalan variant)
      for ok <- ["de-1996", "ca-valencia", "sl-rozaj", "en-fonipa"] do
        assert ^ok = ValidationDerive.validate(:language_code, ok, :lang)
      end
    end

    test "case is informative only — accepts any case (per RFC 5646 §2.1.1)" do
      # BCP-47 recommends lowercase language / titlecase script / uppercase
      # region, but parsers MUST accept any case. We mirror that.
      assert "EN" = ValidationDerive.validate(:language_code, "EN", :lang)
      assert "en-us" = ValidationDerive.validate(:language_code, "en-us", :lang)
      assert "ZH-hant" = ValidationDerive.validate(:language_code, "ZH-hant", :lang)
    end

    test "rejects obvious non-shapes: full names, single letters, digits-only" do
      for bad <- ["english", "e", "1", "12", "123", "fr_FR", "fr/FR", " en", "en "] do
        assert {:error, :lang, :language_code, _} =
                 ValidationDerive.validate(:language_code, bad, :lang),
               "expected :language_code rejection for #{inspect(bad)}"
      end
    end

    test "rejects primary subtag outside 2–3 chars" do
      # 1-char and 4+-char primary subtags are invalid per BCP-47
      for bad <- ["a", "frgh", "abcde"] do
        assert {:error, :lang, :language_code, _} =
                 ValidationDerive.validate(:language_code, bad, :lang),
               "expected :language_code rejection for #{inspect(bad)}"
      end
    end

    test "rejects secondary subtags outside 2–8 chars" do
      # Region/script/variant subtags must be 2–8 alphanumeric
      for bad <- ["en-x", "en-USA1234567890", "en-"] do
        assert {:error, :lang, :language_code, _} =
                 ValidationDerive.validate(:language_code, bad, :lang),
               "expected :language_code rejection for #{inspect(bad)}"
      end
    end

    test "rejects non-binary inputs with explicit error" do
      for bad <- [nil, :en, 123, [], %{}, true] do
        assert {:error, :lang, :language_code, _} =
                 ValidationDerive.validate(:language_code, bad, :lang),
               "expected :language_code rejection for #{inspect(bad)}"
      end
    end

    test "rejects empty string" do
      assert {:error, :lang, :language_code, _} =
               ValidationDerive.validate(:language_code, "", :lang)
    end

    test "compose with sanitize: trim + downcase normalises any user input" do
      sanitized =
        "  EN-US  "
        |> SanitizerDerive.sanitize(:trim)
        |> SanitizerDerive.sanitize(:downcase)

      assert "en-us" = sanitized
      assert "en-us" = ValidationDerive.validate(:language_code, sanitized, :lang)
    end

    test "error message includes the field name and a hint about expected shape" do
      assert {:error, :preferred_language, :language_code, msg} =
               ValidationDerive.validate(:language_code, "english", :preferred_language)

      assert msg =~ "preferred_language"
      assert msg =~ "BCP-47"
    end
  end
end
