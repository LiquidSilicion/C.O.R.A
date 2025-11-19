clear; clc; close all;

% Load WAV file
[audio_data, fs_original] = audioread('on2.wav'); % Replace with your WAV file path

% If stereo, convert to mono
if size(audio_data, 2) > 1
    audio_data = mean(audio_data, 2);
end

% Use original sampling rate (16kHz) or resample if needed for your pipeline
fs_target = 16000; % Using 16kHz as target
if fs_original ~= fs_target
    audio_data = resample(audio_data, fs_target, fs_original);
    fprintf('Resampled from %d Hz to %d Hz\n', fs_original, fs_target);
else
    fprintf('Using original sampling rate: %d Hz\n', fs_target);
end

% Normalize audio data to prevent clipping
audio_data = audio_data / max(abs(audio_data)) * 0.9;

fprintf('=== WAV File Processing (16kHz) ===\n');
fprintf('Sampling Rate: %d Hz\n', fs_target);
fprintf('Audio length: %.2f seconds\n', length(audio_data)/fs_target);
fprintf('Number of samples: %d\n', length(audio_data));

% Process the audio data
fprintf('Processing audio data...\n');

% Step 1: Apply pre-emphasis filter (boost high frequencies)
alpha = 0.92;  % Pre-emphasis coefficient 
emphasized_audio = pre_emphasis_filter_pcm(audio_data, alpha, fs_target);

% Plot results
figure('Position', [50, 50, 1400, 1000]);

% Time domain plots
samples_to_plot = min(2000, length(audio_data));
t = (0:samples_to_plot-1) / fs_target * 1000; % Time in milliseconds

% Original audio signal
subplot(3, 3, 1);
plot(t, audio_data(1:samples_to_plot), 'b-', 'LineWidth', 1.5);
title('Original WAV Audio Signal (16kHz)');
xlabel('Time (ms)'); ylabel('Amplitude');
grid on;

% Emphasized signal
subplot(3, 3, 2);
plot(t, emphasized_audio(1:samples_to_plot), 'r-', 'LineWidth', 1.5);
title('After Pre-emphasis Filter');
xlabel('Time (ms)'); ylabel('Amplitude');
grid on;

% Frequency domain analysis
N_fft = 4096;
f = (0:N_fft/2-1)/N_fft * fs_target;

% Original spectrum
subplot(3, 3, 4);
audio_spectrum = abs(fft(audio_data(1:min(N_fft, length(audio_data))), N_fft));
audio_spectrum_db = 20*log10(audio_spectrum(1:N_fft/2) + eps);
plot(f, audio_spectrum_db, 'b-', 'LineWidth', 1.5);
title('Original Audio Spectrum');
xlabel('Frequency (Hz)'); ylabel('Magnitude (dB)');
xlim([0 fs_target/2]); grid on;

% Emphasized spectrum
subplot(3, 3, 5);
emph_spectrum = abs(fft(emphasized_audio(1:min(N_fft, length(emphasized_audio))), N_fft));
emph_spectrum_db = 20*log10(emph_spectrum(1:N_fft/2) + eps);
plot(f, emph_spectrum_db, 'r-', 'LineWidth', 1.5);
title('Spectrum After Pre-emphasis');
xlabel('Frequency (Hz)'); ylabel('Magnitude (dB)');
xlim([0 fs_target/2]); grid on;

% Comparison
subplot(3, 3, 6);
plot(f, audio_spectrum_db, 'b:', 'LineWidth', 1); hold on;
plot(f, emph_spectrum_db, 'r-', 'LineWidth', 1.5);
legend('Original', 'After Pre-emphasis', 'Location', 'best');
title('Pre-emphasis Effect Comparison');
xlabel('Frequency (Hz)'); ylabel('Magnitude (dB)');
xlim([0 fs_target/2]); grid on;

% Pre-emphasis filter response
subplot(3, 3, 7);
[freq_resp, w] = freqz([1 -alpha], 1, 1024, fs_target);
plot(w, 20*log10(abs(freq_resp)), 'm-', 'LineWidth', 2);
title('Pre-emphasis Filter Frequency Response');
xlabel('Frequency (Hz)'); ylabel('Magnitude (dB)');
grid on;
xlim([0 fs_target/2]); % Show up to 8kHz for 16kHz sampling

% Signal statistics
subplot(3, 3, 8);
stats_labels = {'Original', 'Emphasized'};
stats_std = [std(audio_data), std(emphasized_audio)];
bar(stats_std);
set(gca, 'XTickLabel', stats_labels);
title('Signal Standard Deviation');
ylabel('Std Dev');
grid on;

% Spectrogram
subplot(3, 3, 9);
window = hamming(256); % Smaller window for 16kHz
noverlap = 128;
nfft = 512;
spectrogram(audio_data, window, noverlap, nfft, fs_target, 'yaxis');
title('Spectrogram of Original Audio (16kHz)');
colorbar;

fprintf('\n=== Processing Summary ===\n');
fprintf('Sampling Rate: %d Hz\n', fs_target);
fprintf('Pre-emphasis coefficient: α = %.2f\n', alpha);
fprintf('Total samples processed: %d\n', length(audio_data));
fprintf('Signal duration: %.3f seconds\n', length(audio_data)/fs_target);
fprintf('Dynamic range (original): %.4f\n', max(audio_data) - min(audio_data));
fprintf('Dynamic range (emphasized): %.4f\n', max(emphasized_audio) - min(emphasized_audio));

% Save the processed audio as WAV file
output_filename = 'pre_emphasized_audio_on2.wav';
audiowrite(output_filename, emphasized_audio, fs_target);
fprintf('\n=== Output Saved ===\n');
fprintf('Pre-emphasized audio saved as: %s\n', output_filename);
fprintf('File saved with %d Hz sampling rate\n', fs_target);


function emphasized_signal = pre_emphasis_filter_pcm(input_signal, alpha, fs)
    % Pre-emphasis filter: y[n] = x[n] - alpha * x[n-1]
    % This boosts high frequencies
    
    if nargin < 2
        alpha = 0.92;  % Default pre-emphasis coefficient
    end
    
    if nargin < 3
        fs = 16000;    % 16kHz sampling rate
    end
    
    % Design pre-emphasis filter
    % Transfer function: H(z) = 1 - alpha * z^(-1)
    b = [1, -alpha];
    a = 1;
    
    emphasized_signal = filter(b, a, input_signal);
end