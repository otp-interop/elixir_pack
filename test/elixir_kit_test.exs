defmodule ElixirKitTest do
  use ExUnit.Case
  doctest ElixirKit

  test "greets the world" do
    assert ElixirKit.hello() == :world
  end
end
