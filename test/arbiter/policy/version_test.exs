defmodule Arbiter.Policy.VersionTest do
  use ExUnit.Case, async: true

  alias Arbiter.Policy.Version

  describe "next/1" do
    test "increments policy_v-prefixed integer versions" do
      assert Version.next("policy_v12") == {:ok, "policy_v13"}
    end

    test "fails closed for unsupported version formats" do
      assert Version.next("v12") == {:error, :invalid_policy_version}
      assert Version.next(nil) == {:error, :invalid_policy_version}
    end
  end
end
