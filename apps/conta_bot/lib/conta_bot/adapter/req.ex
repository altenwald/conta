defmodule ContaBot.Adapter.Req do
  @moduledoc """
  HTTP adapter that uses [Req](https://hexdocs.pm/req) for Telegram Bot API requests,
  ensuring multipart form field names are converted to atoms for compatibility with Req.
  """
  @behaviour ExGram.Adapter

  @base_url "https://api.telegram.org"

  @impl ExGram.Adapter
  def request(verb, path, body, opts) do
    req_opts = [
      method: coerce_verb(verb),
      url: path
    ]

    req =
      req_opts
      |> Req.Request.new()
      |> put_finch_options(opts)
      |> Req.Request.register_options([:base_url, :json, :form_multipart, :compressed, :plug])
      |> Req.Request.put_new_option(:compressed, true)
      |> Req.Request.put_new_option(:base_url, ExGram.Config.get(:ex_gram, :base_url, @base_url))
      |> put_body_option(body)
      |> Req.Request.merge_options(opts)
      |> Req.Steps.put_base_url()
      |> Req.Steps.compressed()
      |> Req.Request.append_request_steps(custom_encode: &custom_encode/1)
      |> Req.Request.append_response_steps(
        decompress_body: &Req.Steps.decompress_body/1,
        custom_decode: &custom_decode/1
      )

    req =
      if req.options[:plug] do
        %{req | adapter: &Req.Steps.run_plug/1}
      else
        req
      end

    req
    |> Req.Request.run_request()
    |> handle_result()
  end

  defp put_finch_options(req, opts) do
    connect_options = [timeout: Keyword.get(opts, :connect_timeout, 30_000)]

    finch_options = [
      connect_options: connect_options,
      pool_timeout: Keyword.get(opts, :pool_timeout, 5_000),
      receive_timeout: Keyword.get(opts, :receive_timeout, 60_000),
      finch: Keyword.get(opts, :finch)
    ]

    req
    |> Req.Request.register_options([:connect_options, :pool_timeout, :receive_timeout, :finch])
    |> Req.Request.merge_options(finch_options)
  end

  defp coerce_verb(:get), do: :post
  defp coerce_verb(verb), do: verb

  defp to_atom(name) when is_atom(name), do: name
  defp to_atom(name) when is_binary(name), do: String.to_atom(name)

  defp req_parts({:file, name, path}, parts) do
    parts ++ [{to_atom(name), File.stream!(path, 2048)}]
  end

  defp req_parts({:file_content, name, content, filename}, parts) do
    parts ++ [{to_atom(name), {content, filename: filename}}]
  end

  defp req_parts({name, value}, parts) do
    parts ++ [{to_atom(name), value}]
  end

  defp put_body_option(req, {:multipart, parts}) do
    parts = Enum.reduce(parts, [], fn part, acc -> req_parts(part, acc) end)
    Req.Request.put_new_option(req, :form_multipart, parts)
  end

  defp put_body_option(req, body) when is_map(body) do
    Req.Request.put_new_option(req, :json, body)
  end

  defp custom_encode(request) do
    cond do
      data = request.options[:form_multipart] ->
        multipart = Req.Utils.encode_form_multipart(data)

        %{request | body: multipart.body}
        |> Req.Request.put_new_header("content-type", multipart.content_type)
        |> maybe_put_content_length(multipart.size)

      data = request.options[:json] ->
        %{request | body: ExGram.Adapter.encode(data)}
        |> Req.Request.put_new_header("Content-Type", "application/json")
        |> Req.Request.put_new_header("Accept", "application/json")

      true ->
        request
    end
  end

  defp maybe_put_content_length(req, nil), do: req

  defp maybe_put_content_length(req, size) do
    Req.Request.put_new_header(req, "content-length", Integer.to_string(size))
  end

  defp custom_decode({request, response}) do
    case ExGram.Encoder.decode(response.body, keys: :atoms) do
      {:ok, decoded} ->
        {request, put_in(response.body, decoded)}

      {:error, e} ->
        {request, e}
    end
  end

  defp handle_result({_req, %Req.Response{status: status, body: %{ok: true, result: body}} = _response})
       when status in 200..299 do
    {:ok, body}
  end

  defp handle_result(
         {_req,
          %Req.Response{
            body: %{ok: false, description: description, error_code: error_code} = body
          }}
       ) do
    parameters = maybe_error_parameters(body)

    error = %ExGram.Error{
      code: error_code,
      message: description,
      metadata: %{parameters: parameters}
    }

    {:error, error}
  end

  defp handle_result({_req, %Req.Response{body: body} = _response}) do
    {:error, %ExGram.Error{code: :response_status_not_match, message: ExGram.Adapter.encode(body)}}
  end

  defp handle_result({_req, exception}) do
    {:error,
     %ExGram.Error{
       code: exception,
       message: "Request failed with exception: #{inspect(exception)}"
     }}
  end

  defp maybe_error_parameters(%{parameters: parameters}) do
    case ExGram.Cast.cast(parameters, {:array, ExGram.Model.ResponseParameters}) do
      {:ok, parameters} -> parameters
      _ -> []
    end
  end

  defp maybe_error_parameters(_), do: []
end
