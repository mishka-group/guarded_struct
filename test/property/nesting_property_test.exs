defmodule GuardedStructTest.Property.NestingTest do
  @moduledoc """
  Properties for arbitrarily-deep `sub_field` nesting and the Ash
  auto-map cascade (which forces every nested `sub_field` to return a
  plain map regardless of depth).
  """

  use ExUnit.Case, async: true
  use ExUnitProperties

  alias GuardedStructTest.PropertyFixtures.Deeply
  alias GuardedStructTest.AshResources.WithSubField

  describe "Deeply.builder/1 — five-level sub_field chain" do
    property "valid input at every depth round-trips through the struct cascade" do
      check all(
              tag <- StreamData.string(:alphanumeric, max_length: 16),
              l1 <- StreamData.string(:alphanumeric, max_length: 16),
              l2 <- StreamData.string(:alphanumeric, max_length: 16),
              l3 <- StreamData.string(:alphanumeric, max_length: 16),
              l4 <- StreamData.string(:alphanumeric, max_length: 16),
              l5 <- StreamData.string(:alphanumeric, max_length: 16)
            ) do
        input = %{
          tag: tag,
          l1: %{
            name: l1,
            l2: %{
              name: l2,
              l3: %{
                name: l3,
                l4: %{
                  name: l4,
                  l5: %{name: l5}
                }
              }
            }
          }
        }

        assert {:ok,
                %Deeply{
                  l1: %Deeply.L1{
                    name: ^l1,
                    l2: %Deeply.L1.L2{
                      name: ^l2,
                      l3: %Deeply.L1.L2.L3{
                        name: ^l3,
                        l4: %Deeply.L1.L2.L3.L4{
                          name: ^l4,
                          l5: %Deeply.L1.L2.L3.L4.L5{name: out_l5}
                        }
                      }
                    }
                  }
                }} = Deeply.builder(input)

        # Innermost field has `sanitize(trim, downcase)` applied.
        assert out_l5 == l5 |> String.trim() |> String.downcase()
      end
    end

    property "every intermediate sub_field is a struct of the expected type" do
      check all(name <- StreamData.string(:alphanumeric, min_length: 1, max_length: 12)) do
        input = %{l1: %{name: name, l2: %{name: name, l3: %{name: name}}}}

        assert {:ok, %Deeply{l1: l1}} = Deeply.builder(input)
        assert %Deeply.L1{} = l1
        assert %Deeply.L1.L2{} = l1.l2
        assert %Deeply.L1.L2.L3{} = l1.l2.l3
      end
    end
  end

  describe "Ash auto-map cascade via __guarded_change__/1" do
    property "every nested sub_field is a plain map (never a struct) at every depth" do
      city_gen = StreamData.string(:alphanumeric, max_length: 24)
      name_gen = StreamData.string(:alphanumeric, max_length: 24)
      bio_gen = StreamData.string(:alphanumeric, max_length: 50)
      lat_gen = StreamData.float(min: -90.0, max: 90.0)
      lng_gen = StreamData.float(min: -180.0, max: 180.0)

      check all(
              city <- city_gen,
              name <- name_gen,
              bio <- bio_gen,
              lat <- lat_gen,
              lng <- lng_gen
            ) do
        input = %{
          email: "alice@example.com",
          profile: %{
            name: name,
            bio: bio,
            address: %{
              city: city,
              geo: %{lat: lat, lng: lng}
            }
          }
        }

        assert {:ok, attrs} = WithSubField.__guarded_change__(input)

        assert is_map(attrs)
        refute is_struct(attrs)
        refute is_struct(attrs.profile)
        refute is_struct(attrs.profile.address)
        refute is_struct(attrs.profile.address.geo)

        assert attrs.profile.address.geo.lat == lat
        assert attrs.profile.address.geo.lng == lng
      end
    end
  end
end
