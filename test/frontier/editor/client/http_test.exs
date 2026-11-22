defmodule Frontier.Editor.Client.HTTPTest do
  use ExUnit.Case, async: false

  alias Frontier.Editor.Client.HTTP

  setup do
    previous = Application.get_env(:frontier, HTTP)

    Application.put_env(:frontier, HTTP,
      base_url: "https://example.test/v1",
      model: "test-model",
      api_key: nil
    )

    on_exit(fn ->
      if previous,
        do: Application.put_env(:frontier, HTTP, previous),
        else: Application.delete_env(:frontier, HTTP)
    end)

    :ok
  end

  describe "the request" do
    test "asks for a JSON object from the configured model" do
      assert {:ok, body} =
               HTTP.post_body([%{role: "user", content: "hi"}], api_key: "x", model: "test-model")

      assert body.model == "test-model"
      assert body.response_format == %{type: "json_object"}
      assert body.messages == [%{role: "user", content: "hi"}]
    end
  end

  describe "the reply" do
    test "reads content and token usage" do
      decoded = %{
        "model" => "test-model",
        "choices" => [%{"message" => %{"content" => "{\"ok\": true}"}}],
        "usage" => %{"prompt_tokens" => 1_200, "completion_tokens" => 400}
      }

      assert {:ok, "{\"ok\": true}"} = HTTP.content(decoded)
      assert HTTP.usage(decoded) == %{input_tokens: 1_200, output_tokens: 400}
    end

    test "a reply with no usage records zero, never a guess" do
      assert HTTP.usage(%{"choices" => []}) == %{input_tokens: 0, output_tokens: 0}
    end

    test "an unexpected body is an error, not an edition" do
      assert {:error, {:unexpected_completion, %{"error" => "nope"}}} =
               HTTP.content(%{"error" => "nope"})
    end
  end

  describe "configuration" do
    test "a missing key fails before a request is attempted" do
      assert {:error, :missing_api_key} = HTTP.complete([%{role: "user", content: "hi"}])
    end
  end
end
