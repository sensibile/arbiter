defmodule Arbiter.Policy.AttributesTest do
  use ExUnit.Case, async: true

  alias Arbiter.Policy.Attributes
  alias Arbiter.Tenants.User

  test "fetches string-key map values" do
    assert {:ok, "tenant_a"} =
             Attributes.fetch_required(%{"tenant_id" => "tenant_a"}, "tenant_id")
  end

  test "fetches atom-key map and struct values without creating atoms" do
    user = %User{tenant_id: "tenant_a"}

    assert {:ok, "tenant_a"} = Attributes.fetch_required(%{tenant_id: "tenant_a"}, "tenant_id")
    assert {:ok, "tenant_a"} = Attributes.fetch_required(user, "tenant_id")
  end

  test "fetches nested paths" do
    attrs = %{"user" => %{"profile" => %{"tenant_id" => "tenant_a"}}}

    assert {:ok, "tenant_a"} = Attributes.fetch_path(attrs, ["user", "profile", "tenant_id"])
  end

  test "returns an error for missing required values" do
    assert {:error, :missing_attribute} = Attributes.fetch_required(%{}, "missing")
  end

  test "distinguishes present nil values from missing values" do
    assert {:ok, nil} = Attributes.fetch_present(%{"deleted_at" => nil}, "deleted_at")
    assert {:error, :missing_attribute} = Attributes.fetch_present(%{}, "deleted_at")
  end
end
