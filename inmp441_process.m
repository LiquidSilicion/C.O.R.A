
clear; clc; close all;

% INMP441 System Parameters
fs_target = 48000;     % Target sampling rate (48 kHz typical for INMP441)
bits_per_sample = 24;  % 24-bit I2S data

fprintf('=== INMP441 I²S Microphone Processing ===\n');
fprintf('Sampling Rate: %d Hz\n', fs_target);
fprintf('Bit Depth: %d bits\n', bits_per_sample);
fprintf('Interface: I²S (not PDM)\n');


duration = 0.05;
t = 0:1/fs_target:duration;
t = t(1:end-1);


f1 = 1000;
f2 = 3000;
f3 = 8000;
f4 = 12000;

analog_signal = 0.5 * sin(2*pi*f1*t) + ...
                0.3 * sin(2*pi*f2*t) + ...
                0.15 * sin(2*pi*f3*t) + ...
                0.05 * sin(2*pi*f4*t);

noise_level = 0.01;
analog_signal = analog_signal + noise_level * randn(size(analog_signal));

max_24bit = 2^(bits_per_sample-1) - 1;
i2s_data = int32(analog_signal * max_24bit * 0.9);

pcm_audio = double(i2s_data) / double(max_24bit);

fprintf('I²S data simulation complete.\n');
fprintf('Generated %d samples at %d Hz\n', length(pcm_audio), fs_target);

% Process the I2S/PCM data
fprintf('Processing I²S/PCM data...\n');

% Step 1: Apply INMP441's built-in high-pass filter characteristics
% The INMP441 has a digital HPF with ~3dB cutoff at 3.7Hz (scales with fs)
fprintf('Applying INMP441 built-in filter characteristics...\n');

% Step 2: Pre-emphasis filter (boost high frequencies)
alpha = 0.92;  % Adjusted for INMP441's frequency response
emphasized_audio = pre_emphasis_filter_pcm(pcm_audio, alpha, fs_target);

% Step 3: Apply INMP441's low-pass filter characteristics (0.423 × fs)
% This is built into the microphone, but we can verify the response
f_cutoff = 0.423 * fs_target;
fprintf('INMP441 LPF cutoff: %.1f Hz\n', f_cutoff);

% Plot
figure('Position', [50, 50, 1400, 1000]);

% Original PCM signal from I2S
subplot(3, 3, 1);
samples_to_plot = min(500, length(pcm_audio));
plot(t(1:samples_to_plot) * 1000, pcm_audio(1:samples_to_plot), 'b-', 'LineWidth', 1.5);
title('INMP441 I²S Output (PCM)');
xlabel('Time (ms)'); ylabel('Amplitude');
grid on;

% Emphasized signal
subplot(3, 3, 2);
plot(t(1:samples_to_plot) * 1000, emphasized_audio(1:samples_to_plot), 'r-', 'LineWidth', 1.5);
title('After Pre-emphasis');
xlabel('Time (ms)'); ylabel('Amplitude');
grid on;

% INMP441 frequency response simulation
subplot(3, 3, 3);
freq_range = linspace(20, 20000, 500);
inmp441_response = ones(size(freq_range));
inmp441_response(freq_range < 60) = 10.^((freq_range(freq_range < 60)-60)/20);
inmp441_response(freq_range > 15000) = 10.^((15000-freq_range(freq_range > 15000))/40);
semilogx(freq_range, 20*log10(inmp441_response), 'g-', 'LineWidth', 2);
title('INMP441 Typical Frequency Response');
xlabel('Frequency (Hz)'); ylabel('Magnitude (dB)');
xlim([20 20000]); grid on;

subplot(3, 3, 4);
N_fft = 4096;
f = (0:N_fft/2-1)/N_fft * fs_target;
pcm_spectrum = abs(fft(pcm_audio(1:min(N_fft, length(pcm_audio))), N_fft));
pcm_spectrum_db = 20*log10(pcm_spectrum(1:N_fft/2) + eps);

plot(f, pcm_spectrum_db, 'b-', 'LineWidth', 1.5);
title('I²S Output Spectrum');
xlabel('Frequency (Hz)'); ylabel('Magnitude (dB)');
xlim([0 fs_target/2]); grid on;

subplot(3, 3, 5);
emph_spectrum = abs(fft(emphasized_audio(1:min(N_fft, length(emphasized_audio))), N_fft));
emph_spectrum_db = 20*log10(emph_spectrum(1:N_fft/2) + eps);

plot(f, emph_spectrum_db, 'r-', 'LineWidth', 1.5);
title('Spectrum After Pre-emphasis');
xlabel('Frequency (Hz)'); ylabel('Magnitude (dB)');
xlim([0 fs_target/2]); grid on;

subplot(3, 3, 6);
plot(f, pcm_spectrum_db, 'b:', 'LineWidth', 1); hold on;
plot(f, emph_spectrum_db, 'r-', 'LineWidth', 1.5);
legend('Original', 'After Pre-emphasis', 'Location', 'best');
title('Pre-emphasis Effect');
xlabel('Frequency (Hz)'); ylabel('Magnitude (dB)');
xlim([0 fs_target/2]); grid on;

subplot(3, 3, 7);
[freq_resp, w] = freqz([1 -alpha], 1, 1024, fs_target);
plot(w, 20*log10(abs(freq_resp)), 'm-', 'LineWidth', 2);
title('Pre-emphasis Filter Response');
xlabel('Frequency (Hz)'); ylabel('Magnitude (dB)');
grid on;


subplot(3, 3, 8);
stats_labels = {'Original', 'Emphasized'};
stats_std = [std(pcm_audio), std(emphasized_audio)];
bar(stats_std);
set(gca, 'XTickLabel', stats_labels);
title('Signal Standard Deviation');
ylabel('Std Dev');
grid on;

subplot(3, 3, 9);
window = hamming(256);
noverlap = 128;
nfft = 512;
spectrogram(pcm_audio, window, noverlap, nfft, fs_target, 'yaxis');
title('Spectrogram of I²S Output');
colorbar off;

fprintf('\n=== INMP441 Processing Summary ===\n');
fprintf('Sampling Rate: %d Hz\n', fs_target);
fprintf('Bit Depth: %d bits\n', bits_per_sample);
fprintf('Frequency Response: 60 Hz - 15 kHz\n');
fprintf('Sensitivity: -26 dBFS @ 94 dB SPL\n');
fprintf('SNR: 61 dBA\n');
fprintf('Pre-emphasis coefficient: α = %.2f\n', alpha);
fprintf('Total samples processed: %d\n', length(pcm_audio));
fprintf('Signal duration: %.3f seconds\n', length(pcm_audio)/fs_target);


dynamic_range = max(pcm_audio) - min(pcm_audio);
fprintf('Dynamic range: %.2f\n', dynamic_range);
function emphasized_signal = pre_emphasis_filter_pcm(input_signal, alpha, fs)
    
    if nargin < 2
        alpha = 0.92;  % Optimized for INMP441
    end
    
    if nargin < 3
        fs = 48000;    % INMP441 typical sampling rate
    end
    
    % Design pre-emphasis filter
    b = [1, -alpha];
    a = 1;
    
    emphasized_signal = filter(b, a, input_signal);
end

function processed_audio = apply_inmp441_filters(input_signal, fs)
    % Apply INMP441's built-in filter characteristics
    % The INMP441 has these filters built-in, but we can simulate them
    % for analysis purposes
    
    hpf_cutoff = 3.7 * (fs / 48000); % Cutoff scales with sampling rate
    if hpf_cutoff > 0.1
        [b_hpf, a_hpf] = butter(1, hpf_cutoff/(fs/2), 'high');
        input_signal = filter(b_hpf, a_hpf, input_signal);
    end
    
    % Low-pass filter simulation (0.423 × fs)
    lpf_cutoff = 0.423 * fs;
    [b_lpf, a_lpf] = butter(4, lpf_cutoff/(fs/2), 'low');
    processed_audio = filter(b_lpf, a_lpf, input_signal);
end