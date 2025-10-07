// Nano-Rotations Implementation with Coefficient Set Pₖ = C + jk
clear;
clc;

// ==================== BASIC NANO-ROTATIONS IMPLEMENTATION ====================

function nano_rotations_demo()
    printf("=== Nano-Rotations with Coefficient Set Pₖ = C + jk ===\n\n");
    
    // Parameters
    C = 2 + 3*%i;  // Complex constant
    N = 8;         // Number of coefficients
    k = 0:N-1;     // Index array
    
    // Generate nano-rotation coefficients Pₖ = C + jk
    P = C + %i * k;
    
    printf("Complex Constant C = %s\n", string(C));
    printf("Number of coefficients N = %d\n\n", N);
    
    // Display the coefficient set
    printf("Nano-Rotation Coefficients Pₖ = C + jk:\n");
    printf("k\tReal(Pₖ)\tImag(Pₖ)\t|Pₖ|\t\tPhase(Pₖ)\n");
    printf("--\t--------\t--------\t----\t\t---------\n");
    for i = 1:length(P)
        printf("%d\t%8.4f\t%8.4f\t%8.4f\t%8.4f\n", ...
               i-1, real(P(i)), imag(P(i)), abs(P(i)), atan(imag(P(i)), real(P(i))));
    end
    
    // Visualization
    scf(0);
    clf();
    plot(real(P), imag(P), 'ro-', 'LineWidth', 2, 'MarkerSize', 8);
    plot(real(C), imag(C), 'bs', 'MarkerSize', 10, 'LineWidth', 3);
    xgrid(1, 1, 3);
    ygrid(1, 1, 3);
    xlabel('Real Part');
    ylabel('Imaginary Part');
    title('Nano-Rotation Coefficients Pₖ = C + jk');
    legend('Pₖ coefficients', 'Center C', 2);
    
    // Draw coordinate system
    xmin = min([real(P), real(C)]) - 1;
    xmax = max([real(P), real(C)]) + 1;
    ymin = min([imag(P), imag(C)]) - 1;
    ymax = max([imag(P), imag(C)]) + 1;
    
    re = linspace(xmin, xmax, 10);
    im = linspace(ymin, ymax, 10);
endfunction

// ==================== ADVANCED NANO-ROTATIONS KERNEL ====================

function [kernel, P] = generate_nano_rotation_kernel(C, N, operation_type)
    // Generate nano-rotation kernel with coefficients Pₖ = C + jk
    // operation_type: 'rotation', 'scaling', 'transformation'
    
    k = 0:N-1;
    
    // Generate coefficients Pₖ = C + jk
    P = C + %i * k;
    
    // Create kernel matrix based on operation type
    select operation_type
    case 'rotation'
        // Rotation kernel - using coefficients as rotation operators
        kernel = exp(%i * angle(P));
        
    case 'scaling'
        // Scaling kernel - using magnitudes
        kernel = abs(P);
        
    case 'transformation'
        // Full transformation kernel
        kernel = P;
        
    else
        // Default: identity transformation
        kernel = P;
    end
    
endfunction

// ==================== NANO-ROTATION TRANSFORMS ====================

function [output, kernel_info] = nano_rotation_transform(signal, C, transform_type)
    // Apply nano-rotation transform to input signal
    
    N = length(signal);
    
    // Generate nano-rotation coefficients
    k = 0:N-1;
    P = C + %i * k;
    
    kernel_info = struct();
    kernel_info.coefficients = P;
    kernel_info.magnitudes = abs(P);
    kernel_info.phases = atan(imag(P), real(P));
    
    // Apply different types of transforms
    select transform_type
    case 'direct'
        // Direct multiplication transform
        output = signal .* P;
        
    case 'phase_rotation'
        // Phase-only rotation
        phase_factors = exp(%i * kernel_info.phases);
        output = signal .* phase_factors;
        
    case 'magnitude_scaling'
        // Magnitude-only scaling
        output = signal .* kernel_info.magnitudes;
        
    case 'convolution'
        // Convolution with kernel
        output = conv(signal, P, 'same');
        
    else
        // Default: direct multiplication
        output = signal .* P;
    end
    
endfunction

// ==================== COMPREHENSIVE DEMONSTRATION ====================

function comprehensive_nano_demo()
    printf("=== Comprehensive Nano-Rotations Demonstration ===\n\n");
    
    // Parameters
    C = 1.5 + 2*%i;  // Complex center
    N = 16;          // Signal length
    
    // Generate test signal
    n = 0:N-1;
    signal = sin(2*%pi*0.1*n) + 0.5*sin(2*%pi*0.3*n + %pi/4);
    
    // Generate nano-rotation coefficients
    k = 0:N-1;
    P = C + %i * k;
    
    printf("Complex Center C = %s\n", string(C));
    printf("Signal Length N = %d\n", N);
    printf("Coefficient Range: P₀ = %s to P_%d = %s\n\n", ...
           string(P(1)), N-1, string(P($)));
    
    // Apply different transforms
    transform_types = ['direct', 'phase_rotation', 'magnitude_scaling'];
    
    scf(0);
    clf();
    
    for i = 1:length(transform_types)
        transform_type = transform_types(i);
        
        // Apply transform
        [output, kernel_info] = nano_rotation_transform(signal, C, transform_type);
        
        // Plot results
        subplot(3, 3, (i-1)*3 + 1);
        plot(real(kernel_info.coefficients), imag(kernel_info.coefficients), 'ro-');
        title(sprintf('Coefficients - %s', transform_type));
        xlabel('Real');
        ylabel('Imag');
        
        subplot(3, 3, (i-1)*3 + 2);
        plot(n, real(signal), 'b-', n, real(output), 'r-');
        title(sprintf('Real Part - %s', transform_type));
        legend('Input', 'Output');
        
        subplot(3, 3, (i-1)*3 + 3);
        plot(n, imag(signal), 'b-', n, imag(output), 'r-');
        title(sprintf('Imag Part - %s', transform_type));
        legend('Input', 'Output');
    end
    
    // Analysis of coefficient properties
    printf("=== Coefficient Set Analysis ===\n");
    printf("Mean magnitude: %f\n", mean(abs(P)));
    printf("Std dev of magnitudes: %f\n", stdev(abs(P)));
    printf("Mean phase: %f rad\n", mean(atan(imag(P), real(P))));
    printf("Phase range: %f to %f rad\n", min(atan(imag(P), real(P))), max(atan(imag(P), real(P))));
endfunction

// ==================== NANO-ROTATIONS FOR SIGNAL PROCESSING ====================

function signal_processing_demo()
    printf("=== Nano-Rotations for Signal Processing ===\n\n");
    
    // Create a complex-valued signal
    fs = 1000;  // Sampling frequency
    t = 0:1/fs:1-1/fs;
    N = length(t);
    
    // Complex signal: chirp with amplitude modulation
    signal = (1 + 0.3*sin(2*%pi*2*t)) .* exp(%i * 2*%pi * (50*t + 25*t.^2));
    
    // Different complex centers for experimentation
    centers = [1+1*%i, 2+0*%i, 0+2*%i, 1.5+1.5*%i];
    
    scf(1);
    clf();
    
    for i = 1:length(centers)
        C = centers(i);
        
        // Apply nano-rotation transform
        [transformed, kernel_info] = nano_rotation_transform(signal, C, 'direct');
        
        // Plot results
        subplot(2, 2, i);
        
        // Plot coefficients
        plot(real(kernel_info.coefficients), imag(kernel_info.coefficients), 'ro-');
        hold on;
        plot(real(C), imag(C), 'bs', 'MarkerSize', 10);
        
        xlabel('Real Part');
        ylabel('Imaginary Part');
        title(sprintf('C = %s', string(C)));
        legend('Pₖ coefficients', 'Center C');
        
        // Display kernel statistics
        printf("Center: %s\n", string(C));
        printf("  Coefficient magnitude range: [%f, %f]\n", ...
               min(kernel_info.magnitudes), max(kernel_info.magnitudes));
        printf("  Coefficient phase range: [%f, %f] rad\n\n", ...
               min(kernel_info.phases), max(kernel_info.phases));
    end
    
    // Compare input and transformed signal spectra
    scf(2);
    clf();
    
    C_test = 1 + 1*%i;
    [transformed, kernel_info] = nano_rotation_transform(signal, C_test, 'direct');
    
    // Compute spectra
    f = (0:N-1) * fs/N;
    spec_input = fft(signal);
    spec_transformed = fft(transformed);
    
    subplot(2,2,1);
    plot(t, real(signal), 'b-');
    title('Input Signal - Real Part');
    xlabel('Time (s)');
    
    subplot(2,2,2);
    plot(t, real(transformed), 'r-');
    title('Transformed Signal - Real Part');
    xlabel('Time (s)');
    
    subplot(2,2,3);
    plot(f(1:N/2), abs(spec_input(1:N/2)), 'b-');
    title('Input Spectrum');
    xlabel('Frequency (Hz)');
    
    subplot(2,2,4);
    plot(f(1:N/2), abs(spec_transformed(1:N/2)), 'r-');
    title('Transformed Spectrum');
    xlabel('Frequency (Hz)');
endfunction

// ==================== MATHEMATICAL PROPERTIES ANALYSIS ====================

function mathematical_analysis()
    printf("=== Mathematical Properties of Nano-Rotation Coefficients ===\n\n");
    
    // Analyze different complex centers
    test_centers = [0+0*%i, 1+0*%i, 0+1*%i, 1+1*%i, 2+3*%i];
    N = 10;
    
    scf(3);
    clf();
    
    for i = 1:length(test_centers)
        C = test_centers(i);
        k = 0:N-1;
        P = C + %i * k;
        
        // Calculate mathematical properties
        real_part = real(P);
        imag_part = imag(P);
        magnitudes = abs(P);
        phases = atan(imag_part, real_part);
        
        // Display properties
        printf("Center C = %s:\n", string(C));
        printf("  Real parts: arithmetic progression starting at %f\n", real(C));
        printf("  Imag parts: arithmetic progression starting at %f\n", imag(C));
        printf("  Magnitude progression: non-linear\n");
        printf("  Phase progression: non-linear\n");
        
        // Plot coefficient trajectories
        subplot(2, 3, i);
        plot(real_part, imag_part, 'ro-', 'LineWidth', 2);
        plot(real(C), imag(C), 'bs', 'MarkerSize', 10);
        xlabel('Real');
        ylabel('Imag');
        title(sprintf('C = %s', string(C)));
        grid on;
        
        // Add coordinate annotations
        for j = 1:length(P)
            txt = sprintf('P_{%d}', j-1);
            xstring(real_part(j), imag_part(j), txt);
        end
    end
    
    // Additional analysis: Rate of change
    subplot(2,3,6);
    C_var = 1 + 2*%i;
    k_var = 0:20;
    P_var = C_var + %i * k_var;
    
    // Calculate derivatives (differences)
    dP_dk = diff(P_var);
    dMag_dk = diff(abs(P_var));
    dPhase_dk = diff(atan(imag(P_var), real(P_var)));
    
    plot(k_var(2:$,), abs(dP_dk), 'b-', 'LineWidth', 2);
    hold on;
    plot(k_var(2:$,), dMag_dk, 'r-', 'LineWidth', 2);
    plot(k_var(2:$,), dPhase_dk, 'g-', 'LineWidth', 2);
    
    xlabel('Index k');
    ylabel('Rate of Change');
    title('Coefficient Derivatives');
    legend('|dP/dk|', 'd|P|/dk', 'dPhase/dk');
    grid on;
endfunction

// ==================== MAIN EXECUTION ====================

// Run all demonstrations
printf("Starting Nano-Rotations Implementation...\n\n");

// Basic demonstration
nano_rotations_demo();
execsleep(2000);  // Pause for 2 seconds

// Comprehensive demonstration
comprehensive_nano_demo();
execsleep(2000);  // Pause for 2 seconds

// Signal processing application
signal_processing_demo();
execsleep(2000);  // Pause for 2 seconds

// Mathematical analysis
mathematical_analysis();

printf("\n=== Nano-Rotations Implementation Complete ===\n");
