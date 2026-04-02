defmodule RestaurantDash.Notifications.SMS do
  @moduledoc """
  Twilio SMS client for sending order notifications.

  Operates in mock mode when no Twilio credentials are configured.
  """

  require Logger

  @twilio_api_base "https://api.twilio.com/2010-04-01/Accounts"

  # ─── Public API ──────────────────────────────────────────────────────────

  @doc """
  Send an SMS message to a phone number.

  Returns {:ok, message_sid} in real mode, or {:ok, :mock} in mock mode.
  """
  def send(to, body) when is_binary(to) and is_binary(body) do
    config = get_config()

    if mock_mode?(config) do
      Logger.info("[SMS Mock] To: #{to} | Body: #{body}")
      {:ok, :mock}
    else
      do_send(config, to, body)
    end
  end

  @doc "Returns true if SMS is in mock mode (no Twilio credentials)."
  def mock_mode? do
    mock_mode?(get_config())
  end

  # ─── Private ─────────────────────────────────────────────────────────────

  defp do_send(config, to, body) do
    url = "#{@twilio_api_base}/#{config[:account_sid]}/Messages.json"

    form_body =
      URI.encode_query(%{
        "To" => to,
        "From" => config[:from_number],
        "Body" => body
      })

    case Req.post(url,
           body: form_body,
           headers: [{"content-type", "application/x-www-form-urlencoded"}],
           auth: {:basic, "#{config[:account_sid]}:#{config[:auth_token]}"}
         ) do
      {:ok, %{status: status, body: body}} when status in 200..201 ->
        sid = body["sid"]
        Logger.info("[SMS] Sent to #{to}, SID: #{sid}")
        {:ok, sid}

      {:ok, %{status: status, body: body}} ->
        message = body["message"] || "HTTP #{status}"
        Logger.error("[SMS] Failed to send to #{to}: #{message}")
        {:error, message}

      {:error, reason} ->
        Logger.error("[SMS] Request error: #{inspect(reason)}")
        {:error, inspect(reason)}
    end
  end

  defp get_config do
    Application.get_env(:restaurant_dash, :twilio, [])
  end

  defp mock_mode?(config) do
    is_nil(config[:account_sid]) or config[:account_sid] == "" or
      is_nil(config[:auth_token]) or config[:auth_token] == "" or
      is_nil(config[:from_number]) or config[:from_number] == ""
  end
end
