defmodule Arbiter.Policy.Attributes do
  @moduledoc """
  Safe attribute access for policy and retrieval metadata.

  It supports string-key maps, atom-key maps, and Ecto structs without creating
  atoms from external input.
  """

  def fetch_required(value, key) when is_binary(key) do
    case fetch_optional(value, key) do
      nil -> {:error, :missing_attribute}
      fetched_value -> {:ok, fetched_value}
    end
  end

  def fetch_present(value, key) when is_map(value) and is_binary(key) do
    cond do
      Map.has_key?(value, key) ->
        {:ok, Map.get(value, key)}

      atom_key = existing_atom(key) ->
        if Map.has_key?(value, atom_key) do
          {:ok, Map.get(value, atom_key)}
        else
          {:error, :missing_attribute}
        end

      true ->
        {:error, :missing_attribute}
    end
  end

  def fetch_present(_value, _key), do: {:error, :missing_attribute}

  def fetch_path(value, []), do: {:ok, value}

  def fetch_path(value, [field | rest]) when is_binary(field) do
    with {:ok, next_value} <- fetch_required(value, field) do
      fetch_path(next_value, rest)
    end
  end

  def fetch_optional(value, key) when is_map(value) and is_binary(key) do
    cond do
      Map.has_key?(value, key) ->
        Map.get(value, key)

      atom_key = existing_atom(key) ->
        Map.get(value, atom_key)

      true ->
        nil
    end
  end

  def fetch_optional(_value, _key), do: nil

  defp existing_atom(value) do
    String.to_existing_atom(value)
  rescue
    ArgumentError -> nil
  end
end
