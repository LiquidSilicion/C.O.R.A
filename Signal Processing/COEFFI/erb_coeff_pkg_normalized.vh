// ============================================================
//  erb_coeff_pkg_normalized.vh
//  ERB Filterbank - NORMALIZED Q2.14 Coefficients
//  Peak gain = 1.0 for every channel
//  A1, A2 unchanged | B0,B1,B2 divided by peak gain
//  Replace erb_coeff_pkg.vh with this file in Vivado
// ============================================================

// --- CH1 | fc =  100.00 Hz | BW =  35.49 Hz | gain was 0.9999 ---
`define CH1_B0 ( 16'sd113 )
`define CH1_B1 ( 16'sd0 )
`define CH1_B2 ( 16'sd-113 )
`define CH1_A1 ( 16'sd-32517 )
`define CH1_A2 ( 16'sd16157 )

// --- CH2 | fc =  176.33 Hz | BW =  43.73 Hz | gain was 1.0000 ---
`define CH2_B0 ( 16'sd139 )
`define CH2_B1 ( 16'sd0 )
`define CH2_B2 ( 16'sd-139 )
`define CH2_A1 ( 16'sd-32412 )
`define CH2_A2 ( 16'sd16105 )

// --- CH3 | fc =  270.37 Hz | BW =  53.88 Hz | gain was 0.9999 ---
`define CH3_B0 ( 16'sd172 )
`define CH3_B1 ( 16'sd0 )
`define CH3_B2 ( 16'sd-172 )
`define CH3_A1 ( 16'sd-32244 )
`define CH3_A2 ( 16'sd16041 )

// --- CH4 | fc =  386.24 Hz | BW =  66.39 Hz | gain was 1.0000 ---
`define CH4_B0 ( 16'sd211 )
`define CH4_B1 ( 16'sd0 )
`define CH4_B2 ( 16'sd-211 )
`define CH4_A1 ( 16'sd-31978 )
`define CH4_A2 ( 16'sd15962 )

// --- CH5 | fc =  529.00 Hz | BW =  81.80 Hz | gain was 1.0000 ---
`define CH5_B0 ( 16'sd259 )
`define CH5_B1 ( 16'sd0 )
`define CH5_B2 ( 16'sd-259 )
`define CH5_A1 ( 16'sd-31561 )
`define CH5_A2 ( 16'sd15866 )

// --- CH6 | fc =  704.91 Hz | BW = 100.79 Hz | gain was 1.0000 ---
`define CH6_B0 ( 16'sd318 )
`define CH6_B1 ( 16'sd0 )
`define CH6_B2 ( 16'sd-318 )
`define CH6_A1 ( 16'sd-30915 )
`define CH6_A2 ( 16'sd15748 )

// --- CH7 | fc =  921.64 Hz | BW = 124.18 Hz | gain was 1.0000 ---
`define CH7_B0 ( 16'sd390 )
`define CH7_B1 ( 16'sd0 )
`define CH7_B2 ( 16'sd-390 )
`define CH7_A1 ( 16'sd-29924 )
`define CH7_A2 ( 16'sd15604 )

// --- CH8 | fc = 1188.68 Hz | BW = 153.00 Hz | gain was 1.0000 ---
`define CH8_B0 ( 16'sd478 )
`define CH8_B1 ( 16'sd0 )
`define CH8_B2 ( 16'sd-478 )
`define CH8_A1 ( 16'sd-28421 )
`define CH8_A2 ( 16'sd15428 )

// --- CH9 | fc = 1517.70 Hz | BW = 188.52 Hz | gain was 1.0000 ---
`define CH9_B0 ( 16'sd585 )
`define CH9_B1 ( 16'sd0 )
`define CH9_B2 ( 16'sd-585 )
`define CH9_A1 ( 16'sd-26168 )
`define CH9_A2 ( 16'sd15214 )

// --- CH10 | fc = 1923.09 Hz | BW = 232.28 Hz | gain was 1.0000 ---
`define CH10_B0 ( 16'sd715 )
`define CH10_B1 ( 16'sd0 )
`define CH10_B2 ( 16'sd-715 )
`define CH10_A1 ( 16'sd-22842 )
`define CH10_A2 ( 16'sd14954 )

// --- CH11 | fc = 2422.58 Hz | BW = 286.19 Hz | gain was 1.0000 ---
`define CH11_B0 ( 16'sd873 )
`define CH11_B1 ( 16'sd0 )
`define CH11_B2 ( 16'sd-873 )
`define CH11_A1 ( 16'sd-18040 )
`define CH11_A2 ( 16'sd14639 )

// --- CH12 | fc = 3038.00 Hz | BW = 352.62 Hz | gain was 1.0000 ---
`define CH12_B0 ( 16'sd1063 )
`define CH12_B1 ( 16'sd0 )
`define CH12_B2 ( 16'sd-1063 )
`define CH12_A1 ( 16'sd-11330 )
`define CH12_A2 ( 16'sd14259 )

// --- CH13 | fc = 3796.27 Hz | BW = 434.47 Hz | gain was 1.0000 ---
`define CH13_B0 ( 16'sd1291 )
`define CH13_B1 ( 16'sd0 )
`define CH13_B2 ( 16'sd-1291 )
`define CH13_A1 ( 16'sd-2421 )
`define CH13_A2 ( 16'sd13803 )

// --- CH14 | fc = 4730.55 Hz | BW = 535.31 Hz | gain was 1.0000 ---
`define CH14_B0 ( 16'sd1564 )
`define CH14_B1 ( 16'sd0 )
`define CH14_B2 ( 16'sd-1564 )
`define CH14_A1 ( 16'sd8434 )
`define CH14_A2 ( 16'sd13257 )

// --- CH15 | fc = 5881.68 Hz | BW = 659.56 Hz | gain was 1.0000 ---
`define CH15_B0 ( 16'sd1888 )
`define CH15_B1 ( 16'sd0 )
`define CH15_B2 ( 16'sd-1888 )
`define CH15_A1 ( 16'sd19691 )
`define CH15_A2 ( 16'sd12608 )

// --- CH16 | fc = 7300.00 Hz | BW = 812.65 Hz | gain was 1.0000 ---
`define CH16_B0 ( 16'sd2271 )
`define CH16_B1 ( 16'sd0 )
`define CH16_B2 ( 16'sd-2271 )
`define CH16_A1 ( 16'sd27515 )
`define CH16_A2 ( 16'sd11842 )

