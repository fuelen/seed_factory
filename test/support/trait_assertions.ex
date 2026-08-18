defmodule TraitAssertions do
  import ExUnit.Assertions

  def assert_trait(context, binding_name, expected_traits) when is_list(expected_traits) do
    assert Map.has_key?(context, binding_name),
           "No produced entity bound to #{inspect(binding_name)}"

    current_traits =
      Map.get(context.__seed_factory_meta__.current_traits, binding_name) ||
        raise "No tracked traits for #{inspect(binding_name)}"

    assert Enum.sort(expected_traits) == Enum.sort(current_traits)

    context
  end
end
