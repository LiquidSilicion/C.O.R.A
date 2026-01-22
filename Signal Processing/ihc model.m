clear; clc; close all;

% Start overall timer
total_start_time = tic;

% Load WAV file
load_start_time = tic;
[audio_data, fs_original] = audioread('pre_emphasized_audio_on2.wav'); % Replace with your WAV file path
load_time = toc(load_start_time);

% If stereo, convert to mono
if size(audio_data, 2) > 1
    audio_data = mean(audio_data, 2);
end

% Use original sampling rate (16kHz) or resample if needed for your pipeline
fs_target = 16000; % Using 16kHz as target
if fs_original ~= fs_target
    resample_start_time = tic;
    audio_data = resample(audio_data, fs_target, fs_original);
    resample_time = toc(resample_start_time);
    fprintf('Resampled from %d Hz to %d Hz\n', fs_original, fs_target);
else
    resample_time = 0;
    fprintf('Using original sampling rate: %d Hz\n', fs_target);
end

% Normalize audio data to prevent clipping
audio_data = audio_data / max(abs(audio_data)) * 0.9;

fprintf('=== WAV File Processing (16kHz) ===\n');
fprintf('Sampling Rate: %d Hz\n', fs_target);
fprintf('Audio length: %.2f seconds\n', length(audio_data)/fs_target);
fprintf('Number of samples: %d\n', length(audio_data));

% ========== PROCESSING FREQUENCY CONSTRAINTS ==========
target_freq_mhz = 100; % Target processing frequency in MHz
current_freq_estimate = 2000; % Estimate current CPU frequency in MHz
slowdown_factor = current_freq_estimate / target_freq_mhz; % How much to slow down

fprintf('\n=== PROCESSING FREQUENCY CONSTRAINTS ===\n');
fprintf('Target Frequency:   %d MHz\n', target_freq_mhz);
fprintf('Estimated Current:  %d MHz\n', current_freq_estimate);
fprintf('Slowdown Factor:    %.1fx\n', slowdown_factor);

% Process the audio data
fprintf('\nProcessing audio data...\n');

% ========== IHC MODEL PROCESSING ONLY ==========
fprintf('Applying IHC model processing...\n');

% Step 1: Simulate Basilar Membrane response (simple bandpass filtering)
fprintf('  - Simulating BM displacement...\n');
bm_start_time = tic;
num_channels = 16; % 16 CHANNELS
BM_displacement = simulate_BM_response_slow(audio_data, fs_target, num_channels, slowdown_factor);
bm_time = toc(bm_start_time);

% Step 2: Apply IHC processing chain
fprintf('  - Applying IHC processing chain...\n');
ihc_start_time = tic;
IHC_output = IHC_processing_chain_slow(BM_displacement, fs_target, slowdown_factor);
ihc_time = toc(ihc_start_time);

% ========== END OF IHC PROCESSING ==========

% Plotting timer
plot_start_time = tic;

% Plot results - LARGER FIGURE FOR FULL DURATION
figure('Position', [50, 50, 1600, 1200]);

% Time domain plots - FULL DURATION
samples_to_plot = length(audio_data); % CHANGED: Plot entire duration
t = (0:samples_to_plot-1) / fs_target * 1000; % Time in milliseconds

% Original audio signal
subplot(3, 3, 1);
plot(t, audio_data, 'b-', 'LineWidth', 1);
title('Original WAV Audio Signal (16kHz) - Full Duration');
xlabel('Time (ms)'); ylabel('Amplitude');
grid on;
ylim([-1 1]);
xlim([0 t(end)]);

% IHC Output (first channel - highest frequency)
subplot(3, 3, 2);
plot(t, IHC_output(1, :), 'g-', 'LineWidth', 1);
title('IHC Output (Channel 1 - 8kHz) - Full Duration');
xlabel('Time (ms)'); ylabel('Amplitude');
grid on;
xlim([0 t(end)]);

% IHC Output (last channel - lowest frequency)
subplot(3, 3, 3);
plot(t, IHC_output(end, :), 'r-', 'LineWidth', 1);
title('IHC Output (Channel 16 - 200Hz) - Full Duration');
xlabel('Time (ms)'); ylabel('Amplitude');
grid on;
xlim([0 t(end)]);

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

% ========== IHC channel spectra - ALL 16 CHANNELS ==========
subplot(3, 3, 5);
colors = parula(num_channels); % Different color for each channel
for ch = 1:num_channels
    ihc_spectrum = abs(fft(IHC_output(ch, 1:min(N_fft, size(IHC_output,2))), N_fft));
    ihc_spectrum_db = 20*log10(ihc_spectrum(1:N_fft/2) + eps);
    plot(f, ihc_spectrum_db, 'Color', colors(ch,:), 'LineWidth', 1);
    hold on;
end
title('IHC Output Spectra (16 Channels: 200Hz - 8kHz)');
xlabel('Frequency (Hz)'); ylabel('Magnitude (dB)');
xlim([0 fs_target/2]); grid on;
% Add colorbar to show channel frequencies
c = colorbar;
c.Label.String = 'Channel Frequency';
c.Ticks = linspace(0, 1, 6);
c.TickLabels = {'200Hz', '500Hz', '1kHz', '2kHz', '4kHz', '8kHz'};

% Signal statistics
subplot(3, 3, 6);
stats_labels = {'Original', 'IHC Ch1', 'IHC Ch16'};
stats_std = [std(audio_data), std(IHC_output(1,:)), std(IHC_output(end,:))];
bar(stats_std);
set(gca, 'XTickLabel', stats_labels);
title('Signal Standard Deviation');
ylabel('Std Dev');
grid on;

% Spectrogram of original - FULL DURATION
subplot(3, 3, 7);
window = hamming(256);
noverlap = 128;
nfft = 512;
spectrogram(audio_data, window, noverlap, nfft, fs_target, 'yaxis');
title('Spectrogram of Original Audio - Full Duration');
colorbar;

% ========== UPDATED: BM DISPLACEMENT - ALL 16 CHANNELS - FULL DURATION ==========
subplot(3, 3, 8);
offset_step = 0.4; % Fixed offset step of 0.4
for ch = 1:num_channels
    offset = (ch-1) * offset_step;
    plot(t, BM_displacement(ch, :) + offset, 'LineWidth', 0.5); % Thinner lines for full duration
    hold on;
    % Add channel labels
    text(t(end)+20, offset, sprintf('Ch%d', ch), 'FontSize', 7, ...
         'HorizontalAlignment', 'left', 'VerticalAlignment', 'middle');
end
title('BM Displacement (All 16 Channels) - Full Duration');
xlabel('Time (ms)'); ylabel('Amplitude (with offset)');
grid on;
% Set proper y-axis ticks - CLEANER LABELING
max_offset = (num_channels-1) * offset_step;
yticks(0:0.8:max_offset); % Clean spacing
yticklabels({'0', '0.8', '1.6', '2.4', '3.2', '4.0', '4.8', '5.6', '6.0'});
xlim([0 t(end)]);
ylim([-0.2 max_offset+0.2]); % Add small margin

% All channels IHC output - FULL DURATION
subplot(3, 3, 9);
imagesc(t, 1:num_channels, IHC_output); % Use full duration
colorbar; title('IHC Output All Channels (200Hz-8kHz) - Full Duration');
xlabel('Time (ms)'); ylabel('Channel');
yticks([1, 4, 8, 12, 16]);
yticklabels({'1 (8kHz)', '4', '8', '12', '16 (200Hz)'});

plot_time = toc(plot_start_time);

% ========== TIMING ANALYSIS ==========
total_time = toc(total_start_time);

fprintf('\n=== TIMING ANALYSIS ===\n');
fprintf('File Loading:        %.3f seconds\n', load_time);
if resample_time > 0
    fprintf('Resampling:         %.3f seconds\n', resample_time);
end
fprintf('BM Simulation:      %.3f seconds\n', bm_time);
fprintf('IHC Processing:     %.3f seconds\n', ihc_time);
fprintf('Plot Generation:    %.3f seconds\n', plot_time);
fprintf('Total Processing:   %.3f seconds\n', total_time);

% Calculate real-time performance
audio_duration = length(audio_data)/fs_target;
processing_speed = audio_duration / total_time;
fprintf('\nProcessing Speed:   %.3fx real-time\n', processing_speed);

% Calculate equivalent FPGA performance
clock_cycles_per_sample = (total_time * target_freq_mhz * 1e6) / length(audio_data);
fprintf('Equivalent FPGA:    %.1f cycles/sample at %d MHz\n', clock_cycles_per_sample, target_freq_mhz);

fprintf('\n=== Processing Summary ===\n');
fprintf('Sampling Rate: %d Hz\n', fs_target);
fprintf('Total samples processed: %d\n', length(audio_data));
fprintf('Signal duration: %.3f seconds\n', audio_duration);
fprintf('IHC channels: %d\n', size(IHC_output,1));
fprintf('IHC output range: [%.4f, %.4f]\n', min(IHC_output(:)), max(IHC_output(:)));

% Calculate channel statistics
channel_means = mean(IHC_output, 2);
channel_stds = std(IHC_output, [], 2);
fprintf('\nChannel Statistics:\n');
for ch = 1:num_channels
    fprintf('  Channel %2d: mean=%.4f, std=%.4f\n', ch, channel_means(ch), channel_stds(ch));
end

% ========== Normalize IHC output before saving ==========
save_start_time = tic;
output_filename = 'IHC_output_channel1.wav';
ihc_channel1_normalized = IHC_output(1,:)' / max(abs(IHC_output(1,:))) * 0.9;
audiowrite(output_filename, ihc_channel1_normalized, fs_target);
save_time = toc(save_start_time);

fprintf('\n=== Output Saved ===\n');
fprintf('IHC output (channel 1) saved as: %s\n', output_filename);
fprintf('Normalized range: [%.4f, %.4f]\n', min(ihc_channel1_normalized), max(ihc_channel1_normalized));
fprintf('File Save Time:     %.3f seconds\n', save_time);

% Final total including save time
final_total_time = toc(total_start_time);
fprintf('Final Total Time:   %.3f seconds\n', final_total_time);

% ========== SLOW PROCESSING FUNCTIONS ==========

function BM_displacement = simulate_BM_response_slow(audio, fs, num_channels, slowdown_factor)
    % Simulate Basilar Membrane with artificial delays for 100MHz simulation
    f_min = 200;   % Minimum frequency
    f_max = 8000;  % Maximum frequency
    
    center_freqs = logspace(log10(f_min), log10(f_max), num_channels);
    BM_displacement = zeros(num_channels, length(audio));
    
    fprintf('    Channel center frequencies (200Hz - 8kHz): \n');
    for ch = 1:num_channels
        fc = center_freqs(ch);
        if mod(ch,4) == 1 || ch == num_channels
            fprintf('      Ch %2d: %.0f Hz\n', ch, fc);
        end
        
        % Use appropriate bandwidth for 200Hz-8kHz range
        bw_ratio = 0.15;
        bw = fc * bw_ratio;
        
        % Calculate cutoff frequencies with safety margins
        f_low = max(100, fc - bw/2);
        f_high = min(fs/2 * 0.95, fc + bw/2);
        
        % Normalize frequencies and ensure they're within (0,1)
        f_low_norm = max(0.001, f_low/(fs/2));
        f_high_norm = min(0.999, f_high/(fs/2));
        
        % Only design filter if frequencies are valid
        if f_low_norm < f_high_norm && f_low_norm > 0 && f_high_norm < 1
            [b, a] = butter(2, [f_low_norm, f_high_norm]);
            
            % Simulate slower processing with artificial delay
            samples_processed = 0;
            while samples_processed < length(audio)
                chunk_size = min(64, length(audio) - samples_processed); % Process in chunks
                end_sample = samples_processed + chunk_size;
                
                BM_displacement(ch, samples_processed+1:end_sample) = ...
                    filter(b, a, audio(samples_processed+1:end_sample));
                
                samples_processed = end_sample;
                
                % Artificial delay to simulate 100MHz processing
                if slowdown_factor > 1
                    pause(chunk_size * slowdown_factor * 1e-6); % Microsecond delays
                end
            end
        else
            % Fallback: use simple gain for problematic channels
            fprintf('      Ch %2d: [fallback] ', ch);
            BM_displacement(ch, :) = audio * 0.5;
        end
    end
    
    % Display all channel frequencies
    fprintf('    All channel frequencies: ');
    for ch = 1:num_channels
        fprintf('%.0f ', center_freqs(ch));
    end
    fprintf('\n');
end

function IHC_output = IHC_processing_chain_slow(BM_displacement, fs, slowdown_factor)
    % Core IHC processing chain with artificial delays for 100MHz simulation
    [num_channels, num_samples] = size(BM_displacement);
    
    % 1. BM Velocity Extraction (lateral difference)
    BM_velocity = zeros(size(BM_displacement));
    for ch = 2:num_channels
        BM_velocity(ch, :) = BM_displacement(ch, :) - BM_displacement(ch-1, :);
        
        % Artificial delay for velocity calculation
        if slowdown_factor > 1
            pause(num_samples * slowdown_factor * 1e-7);
        end
    end
    BM_velocity(1, :) = BM_displacement(1, :);
    
    % 2. Nonlinear Compression
    IHC_compressed = nonlinear_compression_slow(BM_velocity, slowdown_factor);
    
    % 3. Adaptation Filter
    IHC_adapted = adaptation_filter_slow(IHC_compressed, fs, slowdown_factor);
    
    % 4. Envelope Extraction
    IHC_envelope = lowpass_filter_slow(IHC_adapted, fs, slowdown_factor);
    
    % Final IHC output (receptor potential)
    IHC_output = max(IHC_envelope, 0);
end

function compressed = nonlinear_compression_slow(velocity, slowdown_factor)
    % Logarithmic compression with artificial delays
    compression_factor = 500;
    gain = 0.5;
    epsilon = 1e-6;
    
    [num_channels, num_samples] = size(velocity);
    compressed = zeros(size(velocity));
    
    for ch = 1:num_channels
        for n = 1:num_samples
            compressed(ch, n) = gain * log(1 + compression_factor * (abs(velocity(ch, n)) + epsilon));
            compressed(ch, n) = compressed(ch, n) .* sign(velocity(ch, n) + epsilon);
            
            % Artificial delay per sample for nonlinear processing
            if slowdown_factor > 1 && mod(n, 10) == 0 % Delay every 10 samples
                pause(slowdown_factor * 1e-6);
            end
        end
    end
end

function adapted = adaptation_filter_slow(compressed, fs, slowdown_factor)
    % Dual-time constant adaptation with artificial delays
    tau_fast = 0.005; tau_slow = 0.050;
    gain_fast = 0.3; gain_slow = 0.1;
    
    alpha_fast = exp(-1/(fs * tau_fast));
    alpha_slow = exp(-1/(fs * tau_slow));
    
    [num_channels, num_samples] = size(compressed);
    adapted = zeros(num_channels, num_samples);
    
    for ch = 1:num_channels
        state_fast = 0; state_slow = 0;
        for n = 1:num_samples
            state_fast = alpha_fast * state_fast + (1 - alpha_fast) * compressed(ch, n);
            state_slow = alpha_slow * state_slow + (1 - alpha_slow) * compressed(ch, n);
            adapted(ch, n) = compressed(ch, n) - gain_fast * state_fast - gain_slow * state_slow;
            
            % Artificial delay per sample for adaptation filter
            if slowdown_factor > 1 && mod(n, 8) == 0 % Delay every 8 samples
                pause(slowdown_factor * 1e-6);
            end
        end
    end
end

function envelope = lowpass_filter_slow(adapted, fs, slowdown_factor)
    % Low-pass filter for envelope extraction with artificial delays
    cutoff_freq = 1200;
    [b, a] = butter(2, cutoff_freq/(fs/2));
    [num_channels, num_samples] = size(adapted);
    envelope = zeros(num_channels, num_samples);
    
    for ch = 1:num_channels
        % Process in chunks to allow artificial delays
        samples_processed = 0;
        while samples_processed < num_samples
            chunk_size = min(128, num_samples - samples_processed);
            end_sample = samples_processed + chunk_size;
            
            envelope(ch, samples_processed+1:end_sample) = ...
                filter(b, a, adapted(ch, samples_processed+1:end_sample));
            
            samples_processed = end_sample;
            
            % Artificial delay for filter processing
            if slowdown_factor > 1
                pause(chunk_size * slowdown_factor * 5e-7);
            end
        end
    end
end
