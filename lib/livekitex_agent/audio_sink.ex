defmodule LivekitexAgent.AudioSink do
  @moduledoc """
  Simple audio sink that buffers PCM16 mono audio and plays it using the host OS player.

  On macOS, uses `afplay` to play a temporary WAV file constructed on the fly.
  """

  require Logger

  @doc """
  Play a list of PCM16 binaries concatenated into a single WAV using afplay.

  Options:
  - :sample_rate (default 16000)
  - :delete (default true) whether to delete temp file after playback
  """
  def play_pcm16(chunks, opts \\ []) when is_list(chunks) do
    data = IO.iodata_to_binary(chunks)
    sample_rate = Keyword.get(opts, :sample_rate, 16_000)
    wav = build_wav(data, sample_rate)

    tmp = Path.join(System.tmp_dir!(), "lk_rt_" <> random_id() <> ".wav")

    with :ok <- File.write(tmp, wav),
         {_, 0} <- System.cmd("afplay", [tmp]) do
      if Keyword.get(opts, :delete, true), do: File.rm(tmp)
      :ok
    else
      {:error, reason} ->
        Logger.error("AudioSink file write error: #{inspect(reason)}")
        {:error, reason}

      {out, code} ->
        Logger.error("afplay failed (#{code}): #{out}")
        {:error, {:afplay_failed, code}}
    end
  end

  defp build_wav(pcm16, sample_rate) do
    num_channels = 1
    bits_per_sample = 16
    byte_rate = sample_rate * num_channels * div(bits_per_sample, 8)
    block_align = num_channels * div(bits_per_sample, 8)
    data_size = byte_size(pcm16)
    riff_size = 36 + data_size

    header =
      <<
        # RIFF header
        # 'RIFF'
        0x52,
        0x49,
        0x46,
        0x46,
        riff_size::little-32,
        # 'WAVE'
        0x57,
        0x41,
        0x56,
        0x45,
        # fmt chunk
        # 'fmt '
        0x66,
        0x6D,
        0x74,
        0x20,
        # Subchunk1Size for PCM
        16::little-32,
        # AudioFormat = 1 (PCM)
        1::little-16,
        num_channels::little-16,
        sample_rate::little-32,
        byte_rate::little-32,
        block_align::little-16,
        bits_per_sample::little-16,
        # data chunk
        # 'data'
        0x64,
        0x61,
        0x74,
        0x61,
        data_size::little-32
      >>

    header <> pcm16
  end

  defp random_id do
    :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)
  end
end
