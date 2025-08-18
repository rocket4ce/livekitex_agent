defmodule Examples.WavReader do
  @moduledoc """
  Minimal WAV reader for PCM16 mono files; returns raw PCM16 samples (binary) and sample rate.
  """

  @spec read_pcm16(String.t()) :: {:ok, %{pcm: binary(), sample_rate: pos_integer()}} | {:error, term()}
  def read_pcm16(path) do
    with {:ok, bin} <- File.read(path),
         {:ok, fmt, data} <- parse(bin) do
      case fmt do
        %{audio_format: 1, num_channels: 1, bits_per_sample: 16} ->
          {:ok, %{pcm: data, sample_rate: fmt.sample_rate}}

        other ->
          {:error, {:unsupported_format, other}}
      end
    end
  end

  defp parse(<<"RIFF", _sz::little-32, "WAVE", rest::binary>>) do
    parse_chunks(rest, %{}, <<>>)
  end

  defp parse(_), do: {:error, :invalid_wav}

  defp parse_chunks(<<>>, fmt, data) when map_size(fmt) > 0 and byte_size(data) > 0, do: {:ok, fmt, data}
  defp parse_chunks(<<>>, _fmt, _data), do: {:error, :incomplete_wav}

  defp parse_chunks(<<"fmt ", len::little-32, body::binary-size(len), rest::binary>>, _fmt, data) do
    fmt = parse_fmt(body)
    parse_chunks(pad2(rest, len), fmt, data)
  end

  defp parse_chunks(<<"data", len::little-32, body::binary-size(len), rest::binary>>, fmt, _data) do
    parse_chunks(pad2(rest, len), fmt, body)
  end

  defp parse_chunks(<<_id::binary-4, len::little-32, _skip::binary-size(len), rest::binary>>, fmt, data) do
    parse_chunks(pad2(rest, len), fmt, data)
  end

  defp pad2(rest, len) do
    if rem(len, 2) == 1, do: binary_part(rest, 1, byte_size(rest) - 1), else: rest
  end

  defp parse_fmt(<<
         audio_format::little-16,
         num_channels::little-16,
         sample_rate::little-32,
         byte_rate::little-32,
         block_align::little-16,
         bits_per_sample::little-16,
         rest::binary
       >>) do
    _extra = rest
    %{
      audio_format: audio_format,
      num_channels: num_channels,
      sample_rate: sample_rate,
      byte_rate: byte_rate,
      block_align: block_align,
      bits_per_sample: bits_per_sample
    }
  end
end
