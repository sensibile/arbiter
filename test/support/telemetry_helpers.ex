defmodule Arbiter.TelemetryHelpers do
  use Boundary,
    top_level?: true,
    deps: []

  @moduledoc false

  def attach_telemetry(event, message_tag, opts \\ [])
      when is_list(event) and is_atom(message_tag) do
    test_pid = self()
    handler_id = {__MODULE__, test_pid, message_tag, System.unique_integer([:positive])}

    :ok =
      :telemetry.attach(
        handler_id,
        event,
        fn _event, measurements, metadata, pid ->
          send(pid, {message_tag, measurements, metadata})
        end,
        Keyword.get(opts, :pid, test_pid)
      )

    ExUnit.Callbacks.on_exit(fn -> :telemetry.detach(handler_id) end)
  end
end
