import subprocess
import os
import sys

# Directory for images
IMG_DIR = os.path.abspath("50%_report/images")
os.makedirs(IMG_DIR, exist_ok=True)

# 1. Top-Level Winograd Block Diagram
diagram_top_tex = r"""\documentclass[border=10pt]{standalone}
\usepackage{amsmath,amssymb}
\usepackage{tikz}
\usetikzlibrary{shapes.geometric, arrows.meta, positioning, calc, fit, backgrounds, decorations.pathreplacing}

\begin{document}
\begin{tikzpicture}[
    font=\sffamily,
    >=Stealth,
    node distance=1.6cm and 1.8cm,
    block/.style={draw=blue!70!black, fill=blue!8, line width=1.2pt, rounded corners=4pt, text centered, inner sep=6pt},
    reg/.style={draw=gray!80, fill=gray!20, line width=1pt, rounded corners=2pt, minimum height=1.8cm, minimum width=0.5cm, inner sep=2pt, text centered},
    ctrl/.style={draw=red!70!black, fill=red!8, line width=1.2pt, rounded corners=4pt, text centered, inner sep=6pt},
    bus/.style={line width=1.3pt, ->},
    ctrlbus/.style={line width=1pt, dashed, red!70!black, ->},
    labelstyle/.style={font=\small\sffamily, fill=white, inner sep=1.5pt}
]

    % Coordinates & Inputs
    \node (d_in) at (0, 3.2) {\textbf{d\_tile} $[0:3][0:3]$ \\ \small 16 $\times$ INT16};
    \node (u_in) at (0, 0.8) {\textbf{u\_tile} $[0:3][0:3]$ \\ \small 16 $\times$ INT16 ($U=GgG^T$)};
    \node (ctrl_in) at (0, -1.8) {\textbf{Control Inputs} \\ \small \texttt{start}, \texttt{first\_ch}, \texttt{last\_ch}, \texttt{cin\_count}};

    % Stage 1: Input Transform Unit
    \node[block, minimum width=3.4cm, minimum height=2.4cm, right=1.6cm of d_in] (in_trans) {
        \textbf{Input Transform Unit}\\
        \textbf{\texttt{input\_transform\_2d}}\\
        \vspace{0.15cm}
        \small $V = B^T d B$\\
        \footnotesize Multiplierless 1D Col $\to$ 1D Row\\
        \footnotesize Addition/Subtraction Trees
    };

    % Pipeline Reg 1 (V)
    \node[reg, right=1.2cm of in_trans] (reg_v) {\rotatebox{90}{\textbf{REG (18b)}}};

    % Delay Reg 1 (U)
    \node[reg, right=4.0cm of u_in] (reg_u1) {\rotatebox{90}{\textbf{REG (16b)}}};

    % Stage 2: Multiplier Array
    \node[block, minimum width=3.4cm, minimum height=2.8cm, right=1.4cm of reg_v, yshift=-1.2cm] (mul_array) {
        \textbf{Multiplier Array}\\
        \textbf{\texttt{multiplier\_array}}\\
        \vspace{0.15cm}
        \small $M = U \odot V$\\
        \footnotesize 16 Parallel Signed Multipliers\\
        \footnotesize INT18 $\times$ INT16 $\to$ INT34\\
        \footnotesize (Configurable 4, 8, 16 DSPs)
    };

    % Pipeline Reg 2 (M)
    \node[reg, right=1.2cm of mul_array] (reg_m) {\rotatebox{90}{\textbf{REG (34b)}}};

    % Stage 3: Channel Accumulator
    \node[block, minimum width=3.2cm, minimum height=2.4cm, right=1.2cm of reg_m] (accum) {
        \textbf{Channel Accumulator}\\
        \textbf{\texttt{channel\_accumulator}}\\
        \vspace{0.15cm}
        \small $M_{\text{accum}} = \sum_{c=1}^{C_{\text{in}}} U^{(c)} \odot V^{(c)}$\\
        \footnotesize 16 Parallel 36-bit Accumulators\\
        \footnotesize Partial Sum Storage
    };

    % Pipeline Reg 3 (Accum)
    \node[reg, right=1.2cm of accum] (reg_accum) {\rotatebox{90}{\textbf{REG (36b)}}};

    % Stage 4: Output Transform Unit
    \node[block, minimum width=3.6cm, minimum height=2.8cm, right=1.2cm of reg_accum] (out_trans) {
        \textbf{Output Transform Unit}\\
        \textbf{\texttt{output\_transform\_2d}}\\
        \vspace{0.15cm}
        \small $Y = A^T M_{\text{accum}} A$\\
        \footnotesize Multiplierless 1D Col $\to$ 1D Row\\
        \footnotesize Add/Sub Trees $\to$ \texttt{Shift(>>>6)}\\
        \footnotesize Saturation Logic to INT16
    };

    % Output
    \node[right=1.5cm of out_trans] (y_out) {
        \textbf{y\_tile} $[0:1][0:1]$\\
        \small 4 $\times$ INT16 ($2 \times 2$ Output)\\
        \small \texttt{out\_valid}
    };

    % Controller Block
    \node[ctrl, minimum width=7.5cm, minimum height=1.8cm, below=2.6cm of mul_array] (fsm_ctrl) {
        \textbf{Winograd FSM Controller (\texttt{winograd\_controller})}\\
        \small States: \texttt{IDLE} $\to$ \texttt{PROCESS} $\to$ \texttt{WAIT\_DRAIN} $\to$ \texttt{DONE}\\
        \footnotesize Handshakes: \texttt{in\_ready}, \texttt{first\_channel}, \texttt{last\_channel}, \texttt{tile\_done}
    };

    % Connecting Busses
    \draw[bus] (d_in) -- node[above, font=\footnotesize] {16 $\times$ 16b} (in_trans.west);
    \draw[bus] (in_trans.east) -- node[above, font=\footnotesize] {16 $\times$ 18b} (reg_v.west);
    \draw[bus] (reg_v.east) -- ++(0.5,0) |- node[pos=0.3, above, font=\footnotesize] {$V$ [17:0]} (mul_array.160);

    \draw[bus] (u_in) -- node[above, font=\footnotesize] {16 $\times$ 16b} (reg_u1.west);
    \draw[bus] (reg_u1.east) -- ++(0.5,0) |- node[pos=0.3, below, font=\footnotesize] {$U$ [15:0]} (mul_array.200);

    \draw[bus] (mul_array.east) -- node[above, font=\footnotesize] {16 $\times$ 34b} (reg_m.west);
    \draw[bus] (reg_m.east) -- node[above, font=\footnotesize] {$M$ [33:0]} (accum.west);
    \draw[bus] (accum.east) -- node[above, font=\footnotesize] {16 $\times$ 36b} (reg_accum.west);
    \draw[bus] (reg_accum.east) -- node[above, font=\footnotesize] {$M_{\text{accum}}$} (out_trans.west);
    \draw[bus] (out_trans.east) -- node[above, font=\footnotesize] {4 $\times$ 16b} (y_out.west);

    % Control Connections
    \draw[ctrlbus] (ctrl_in.east) -- ++(1.0,0) |- (fsm_ctrl.west);
    \draw[ctrlbus] (fsm_ctrl.north) -- node[right, font=\footnotesize] {\texttt{first\_ch\_d2, last\_ch\_d2}} (accum.south);
    \draw[ctrlbus] (fsm_ctrl.north -| reg_u1.south) -- (reg_u1.south);
    \draw[ctrlbus] ($(fsm_ctrl.north west)!0.7!(fsm_ctrl.north)$) -- ++(0,1.2) -| (in_trans.south);
    \draw[ctrlbus] ($(fsm_ctrl.north east)!0.3!(fsm_ctrl.north)$) -| (out_trans.south);

    % Top-level Boundary
    \begin{scope}[on background layer]
        \node[draw=blue!40, fill=blue!2, dashed, line width=1.5pt, rounded corners=8pt,
              fit=(in_trans) (out_trans) (y_out) (fsm_ctrl) (reg_u1) (reg_v),
              inner sep=16pt,
              label={[font=\bfseries\large\color{blue!80!black}, anchor=north west]north west:Top-Level Pipelined Winograd Accelerator Core (\texttt{winograd\_top.sv})}] (top_box) {};
    \end{scope}

\end{tikzpicture}
\end{document}
"""

# 2. 2D Input Transform Microarchitecture
diagram_in_trans_tex = r"""\documentclass[border=10pt]{standalone}
\usepackage{tikz}
\usetikzlibrary{shapes.geometric, arrows.meta, positioning, calc, fit, backgrounds}

\begin{document}
\begin{tikzpicture}[
    font=\sffamily,
    >=Stealth,
    node distance=1.4cm and 1.6cm,
    block/.style={draw=teal!70!black, fill=teal!8, line width=1.2pt, rounded corners=4pt, text centered, inner sep=6pt},
    reg/.style={draw=gray!80, fill=gray!20, line width=1pt, rounded corners=2pt, minimum height=2.2cm, minimum width=0.5cm, inner sep=2pt, text centered},
    bus/.style={line width=1.3pt, ->}
]

    % Input
    \node (din) at (0, 2) {\textbf{Input Tile $d$}\\ \small 4 $\times$ 4 INT16 (Signed)};

    % 1D Col Transform
    \node[block, minimum width=4.0cm, minimum height=3.0cm, right=1.5cm of din] (col_trans) {
        \textbf{4 $\times$ 1D Column Transforms}\\
        \textbf{\texttt{input\_transform\_1d}}\\
        \vspace{0.15cm}
        \small $W = B^T \cdot d$\\
        \footnotesize $w_0 = d_0 - d_2$\\
        \footnotesize $w_1 = d_1 + d_2$\\
        \footnotesize $w_2 = d_2 - d_1$\\
        \footnotesize $w_3 = d_1 - d_3$\\
        \vspace{0.1cm}
        \footnotesize Bit-growth: $16 \to 17$ bits
    };

    % Transposition Matrix / Rewiring
    \node[block, fill=orange!8, draw=orange!70!black, minimum width=2.4cm, minimum height=2.6cm, right=1.2cm of col_trans] (transp) {
        \textbf{Spatial Transpose}\\
        \textbf{Rewiring}\\
        \vspace{0.15cm}
        \small $W^T = (B^T d)^T$\\
        \footnotesize Parallel bus permutation\\
        \footnotesize (Zero logic overhead)
    };

    % 1D Row Transform
    \node[block, minimum width=4.0cm, minimum height=3.0cm, right=1.2cm of transp] (row_trans) {
        \textbf{4 $\times$ 1D Row Transforms}\\
        \textbf{\texttt{input\_transform\_1d}}\\
        \vspace{0.15cm}
        \small $V = B^T \cdot W^T$\\
        \footnotesize $v_0 = w_0 - w_2$\\
        \footnotesize $v_1 = w_1 + w_2$\\
        \footnotesize $v_2 = w_2 - w_1$\\
        \footnotesize $v_3 = w_1 - w_3$\\
        \vspace{0.1cm}
        \footnotesize Bit-growth: $17 \to 18$ bits
    };

    % Pipeline Registers
    \node[reg, right=1.2cm of row_trans] (out_reg) {\rotatebox{90}{\textbf{PIPE REG (18b)}}};

    % Output
    \node[right=1.2cm of out_reg] (vout) {\textbf{Transformed Tile $V$}\\ \small 4 $\times$ 4 INT18 (Signed)};

    % Busses
    \draw[bus] (din) -- node[above, font=\footnotesize] {16 $\times$ 16b} (col_trans.west);
    \draw[bus] (col_trans.east) -- node[above, font=\footnotesize] {16 $\times$ 17b} (transp.west);
    \draw[bus] (transp.east) -- node[above, font=\footnotesize] {16 $\times$ 17b} (row_trans.west);
    \draw[bus] (row_trans.east) -- node[above, font=\footnotesize] {16 $\times$ 18b} (out_reg.west);
    \draw[bus] (out_reg.east) -- node[above, font=\footnotesize] {16 $\times$ 18b} (vout.west);

    \begin{scope}[on background layer]
        \node[draw=teal!50, fill=teal!2, dashed, line width=1.4pt, rounded corners=6pt,
              fit=(col_trans) (transp) (row_trans) (out_reg),
              inner sep=14pt,
              label={[font=\bfseries\color{teal!80!black}, anchor=north west]north west:Multiplierless 2D Input Transformation Unit (\texttt{input\_transform\_2d.sv})}] {};
    \end{scope}

\end{tikzpicture}
\end{document}
"""

# 3. 2D Output Transform Microarchitecture
diagram_out_trans_tex = r"""\documentclass[border=10pt]{standalone}
\usepackage{tikz}
\usetikzlibrary{shapes.geometric, arrows.meta, positioning, calc, fit, backgrounds}

\begin{document}
\begin{tikzpicture}[
    font=\sffamily,
    >=Stealth,
    node distance=1.4cm and 1.6cm,
    block/.style={draw=purple!70!black, fill=purple!8, line width=1.2pt, rounded corners=4pt, text centered, inner sep=6pt},
    reg/.style={draw=gray!80, fill=gray!20, line width=1pt, rounded corners=2pt, minimum height=2.2cm, minimum width=0.5cm, inner sep=2pt, text centered},
    bus/.style={line width=1.3pt, ->}
]

    % Input
    \node (min) at (0, 2) {\textbf{Accumulated $M$}\\ \small 4 $\times$ 4 INT36 (Signed)};

    % 1D Col Transform
    \node[block, minimum width=3.8cm, minimum height=2.8cm, right=1.4cm of min] (col_trans) {
        \textbf{4 $\times$ 1D Col Transforms}\\
        \textbf{\texttt{output\_transform\_1d}}\\
        \vspace{0.15cm}
        \small $P = A^T \cdot M$\\
        \footnotesize $p_0 = m_0 + m_1 + m_2$\\
        \footnotesize $p_1 = m_1 - m_2 - m_3$\\
        \vspace{0.1cm}
        \footnotesize Dim: $4 \times 4 \to 2 \times 4$ (38b)
    };

    % Pipeline Reg Stage 1
    \node[reg, right=1.0cm of col_trans] (reg1) {\rotatebox{90}{\textbf{REG STAGE 1 (38b)}}};

    % Transpose
    \node[block, fill=orange!8, draw=orange!70!black, minimum width=2.2cm, minimum height=2.4cm, right=1.0cm of reg1] (transp) {
        \textbf{Transpose}\\
        \vspace{0.15cm}
        \small $P^T$\\
        \footnotesize Bus rewiring\\
        \footnotesize $2 \times 4 \to 4 \times 2$
    };

    % 1D Row Transform
    \node[block, minimum width=3.8cm, minimum height=2.8cm, right=1.0cm of transp] (row_trans) {
        \textbf{2 $\times$ 1D Row Transforms}\\
        \textbf{\texttt{output\_transform\_1d}}\\
        \vspace{0.15cm}
        \small $Y' = A^T \cdot P^T$\\
        \footnotesize $y'_0 = p'_0 + p'_1 + p'_2$\\
        \footnotesize $y'_1 = p'_1 - p'_2 - p'_3$\\
        \vspace{0.1cm}
        \footnotesize Dim: $4 \times 2 \to 2 \times 2$ (40b)
    };

    % Scaling & Saturation
    \node[block, fill=red!8, draw=red!70!black, minimum width=3.2cm, minimum height=2.8cm, right=1.0cm of row_trans] (sat_block) {
        \textbf{Scaling \& Saturation}\\
        \vspace{0.15cm}
        \footnotesize Arithmetic Right Shift:\\
        \small \texttt{>>> 6} ($1/64$ scale factor)\\
        \vspace{0.1cm}
        \footnotesize Clamp to Signed INT16:\\
        \small $[-32768, +32767]$
    };

    % Pipeline Reg Stage 2
    \node[reg, right=1.0cm of sat_block] (reg2) {\rotatebox{90}{\textbf{REG STAGE 2 (16b)}}};

    % Output
    \node[right=1.2cm of reg2] (yout) {\textbf{Output Tile $Y$}\\ \small 2 $\times$ 2 INT16\\ \small \texttt{out\_valid}};

    % Busses
    \draw[bus] (min) -- node[above, font=\footnotesize] {16 $\times$ 36b} (col_trans.west);
    \draw[bus] (col_trans.east) -- node[above, font=\footnotesize] {8 $\times$ 38b} (reg1.west);
    \draw[bus] (reg1.east) -- (transp.west);
    \draw[bus] (transp.east) -- node[above, font=\footnotesize] {8 $\times$ 38b} (row_trans.west);
    \draw[bus] (row_trans.east) -- node[above, font=\footnotesize] {4 $\times$ 40b} (sat_block.west);
    \draw[bus] (sat_block.east) -- node[above, font=\footnotesize] {4 $\times$ 16b} (reg2.west);
    \draw[bus] (reg2.east) -- node[above, font=\footnotesize] {4 $\times$ 16b} (yout.west);

    \begin{scope}[on background layer]
        \node[draw=purple!50, fill=purple!2, dashed, line width=1.4pt, rounded corners=6pt,
              fit=(col_trans) (reg1) (transp) (row_trans) (sat_block) (reg2),
              inner sep=14pt,
              label={[font=\bfseries\color{purple!80!black}, anchor=north west]north west:Multiplierless 2D Output Transform Unit (\texttt{output\_transform\_2d.sv})}] {};
    \end{scope}

\end{tikzpicture}
\end{document}
"""

# 4. FSM State Transition Diagram
diagram_fsm_tex = r"""\documentclass[border=10pt]{standalone}
\usepackage{tikz}
\usetikzlibrary{shapes.geometric, arrows.meta, positioning, calc, backgrounds}

\begin{document}
\begin{tikzpicture}[
    font=\sffamily,
    >=Stealth,
    node distance=2.5cm and 3.5cm,
    state/.style={draw=blue!70!black, fill=blue!10, line width=1.4pt, rounded corners=8pt, minimum width=3.8cm, minimum height=1.8cm, text centered, inner sep=6pt},
    trans/.style={line width=1.2pt, ->}
]

    % States
    \node[state] (idle) {
        \textbf{IDLE} (2'b00)\\
        \vspace{0.1cm}
        \small \texttt{ready = 1'b1}\\
        \small \texttt{channel\_valid = 1'b0}\\
        \small \texttt{tile\_done = 1'b0}
    };

    \node[state, right=3.5cm of idle] (process) {
        \textbf{PROCESS} (2'b01)\\
        \vspace{0.1cm}
        \small \texttt{channel\_valid = 1'b1}\\
        \small \texttt{ch\_cnt++}\\
        \footnotesize \texttt{first\_ch = (ch\_cnt==0)}\\
        \footnotesize \texttt{last\_ch = (ch\_cnt==cin-1)}
    };

    \node[state, below=2.5cm of process] (wait_drain) {
        \textbf{WAIT\_DRAIN} (2'b10)\\
        \vspace{0.1cm}
        \small \texttt{ready = 1'b0}\\
        \small \texttt{channel\_valid = 1'b0}\\
        \footnotesize Wait for pipeline empty
    };

    \node[state, below=2.5cm of idle] (done) {
        \textbf{DONE} (2'b11)\\
        \vspace{0.1cm}
        \small \texttt{tile\_done = 1'b1}\\
        \small \texttt{ready = 1'b0}
    };

    % Transitions
    \draw[trans] (idle) -- node[above, font=\small] {\texttt{start == 1}} (process);
    \draw[trans] (idle) edge[loop above] node[above, font=\small] {\texttt{start == 0}} (idle);

    \draw[trans] (process) edge[loop right] node[right, font=\small] {\texttt{ch\_cnt < cin\_count-1}} (process);
    \draw[trans] (process) -- node[right, font=\small] {\texttt{last\_channel (ch\_cnt == cin-1)}} (wait_drain);

    \draw[trans] (wait_drain) edge[loop right] node[right, font=\small] {\texttt{pipe\_busy == 1}} (wait_drain);
    \draw[trans] (wait_drain) -- node[below, font=\small] {\texttt{!pipe\_busy}} (done);

    \draw[trans] (done) -- node[left, font=\small] {unconditional (1 cycle)} (idle);

    % Reset input
    \draw[trans, red!70!black, line width=1.3pt] ($(idle.north west)+(-1, 0.8)$) -- node[pos=0.2, above, font=\small\bfseries\color{red!70!black}] {\texttt{rst\_n == 0}} (idle.north west);

\end{tikzpicture}
\end{document}
"""

# 5. Verification Flow Diagram
diagram_verif_tex = r"""\documentclass[border=10pt]{standalone}
\usepackage{amsmath,amssymb}
\usepackage{tikz}
\usetikzlibrary{shapes.geometric, arrows.meta, positioning, calc, fit, backgrounds}

\begin{document}
\begin{tikzpicture}[
    font=\sffamily,
    >=Stealth,
    node distance=1.4cm and 1.6cm,
    block/.style={draw=blue!70!black, fill=blue!8, line width=1.2pt, rounded corners=4pt, text centered, inner sep=6pt},
    fileblock/.style={draw=green!60!black, fill=green!8, line width=1.2pt, text centered, inner sep=5pt},
    simblock/.style={draw=purple!70!black, fill=purple!8, line width=1.2pt, rounded corners=4pt, text centered, inner sep=6pt},
    passblock/.style={draw=green!60!black, fill=green!15, line width=1.4pt, rounded corners=6pt, text centered, inner sep=8pt},
    bus/.style={line width=1.3pt, ->}
]

    % Software Domain
    \node[block, minimum width=4.5cm] (py_model) {
        \textbf{Python Float32 Reference}\\
        \textbf{\texttt{winograd.py} / \texttt{direct\_conv.py}}\\
        \footnotesize Standard Winograd algorithm
    };

    \node[block, minimum width=4.5cm, below=1.0cm of py_model] (fixed_model) {
        \textbf{INT16 Fixed-Point Model}\\
        \textbf{\texttt{fixed\_point.py}}\\
        \footnotesize Emulates bit-growth, shifts, saturation
    };

    \node[block, minimum width=4.5cm, below=1.0cm of fixed_model] (gen_vec) {
        \textbf{Test Vector Generator}\\
        \textbf{\texttt{generate\_vectors.py}}\\
        \footnotesize Randomized matrices \& stimuli
    };

    % Files Exported
    \node[fileblock, right=1.6cm of fixed_model, yshift=0.8cm] (hex_in) {\textbf{\texttt{input.hex}}};
    \node[fileblock, right=1.6cm of fixed_model, yshift=-0.0cm] (hex_w) {\textbf{\texttt{weight.hex}}};
    \node[fileblock, right=1.6cm of fixed_model, yshift=-0.8cm] (hex_exp) {\textbf{\texttt{expected\_output.hex}}};

    % RTL Simulation Domain
    \node[simblock, minimum width=4.8cm, right=1.6cm of hex_w] (tb) {
        \textbf{Self-Checking SystemVerilog TB}\\
        \textbf{\texttt{winograd\_core\_tb.sv}}\\
        \footnotesize File I/O, Handshake sequencing
    };

    \node[simblock, minimum width=4.8cm, below=1.0cm of tb] (rtl_dut) {
        \textbf{Device Under Test (DUT)}\\
        \textbf{\texttt{winograd\_top.sv}}\\
        \footnotesize Pipelined RTL Datapath + FSM
    };

    % Assertion & Status
    \node[passblock, draw=green!60!black, fill=green!15, minimum width=5.0cm, right=1.6cm of tb] (checker) {
        \textbf{Bit-Exact Assertion Checker}\\
        \vspace{0.1cm}
        \small Compare \texttt{y\_tile} vs \texttt{expected\_output}\\
        \small Automated mismatch counter\\
        \vspace{0.15cm}
        \large\textbf{\color{green!50!black}[PASSED] 0 Mismatches}
    };

    % Connections
    \draw[bus] (py_model) -- node[right, font=\footnotesize] {Cross-validation} (fixed_model);
    \draw[bus] (fixed_model) -- (gen_vec);
    \draw[bus] (gen_vec.east) -- ++(0.5,0) |- (hex_in.west);
    \draw[bus] (gen_vec.east) -- (hex_w.west);
    \draw[bus] (gen_vec.east) -- ++(0.5,0) |- (hex_exp.west);

    \draw[bus] (hex_in.east) -- (tb.170);
    \draw[bus] (hex_w.east) -- (tb.190);
    \draw[bus] (hex_exp.east) -- ++(0.6,0) |- (checker.west);

    \draw[bus] (tb.south) -- node[right, font=\footnotesize] {Stimulus (\texttt{d\_tile}, \texttt{u\_tile})} (rtl_dut.north);
    \draw[bus] (rtl_dut.east) -| node[pos=0.3, right, font=\footnotesize] {Hardware Output (\texttt{y\_tile})} (checker.south);
    \draw[bus] (tb.east) -- node[above, font=\footnotesize] {\texttt{exp\_data}} (checker.west);

    % Background Groups
    \begin{scope}[on background layer]
        \node[draw=blue!40, fill=blue!2, dashed, line width=1.2pt, rounded corners=6pt,
              fit=(py_model) (gen_vec),
              inner sep=8pt,
              label={[font=\bfseries\color{blue!80!black}, anchor=north]north:Software Golden Modeling}] {};

        \node[draw=purple!40, fill=purple!2, dashed, line width=1.2pt, rounded corners=6pt,
              fit=(tb) (rtl_dut) (checker),
              inner sep=8pt,
              label={[font=\bfseries\color{purple!80!black}, anchor=north]north:Automated Hardware Simulation}] {};
    \end{scope}

\end{tikzpicture}
\end{document}
"""

# 6. Pipeline Timing Diagram (tikz-timing)
diagram_timing_tex = r"""\documentclass[border=10pt]{standalone}
\usepackage{tikz}
\usetikzlibrary{arrows.meta}
\usepackage{tikz-timing}

\begin{document}
\begin{tikztimingtable}[
    timing/slope=0.1,
    timing/dslope=0.2,
    xscale=1.4,
    yscale=1.1,
    timing/rowdist=2.2ex
]
    \textbf{clk}            & 14{C} \\
    \textbf{rst\_n}          & 1{L} 13{H} \\
    \textbf{in\_valid}       & 1{L} 4{H} 9{L} \\
    \textbf{in\_ready}       & 14{H} \\
    \textbf{d\_tile} (Input) & 1{U} 1{D{Tile 0}} 1{D{Tile 1}} 1{D{Tile 2}} 1{D{Tile 3}} 9{U} \\
    \textbf{u\_tile} (Weight)& 1{U} 1{D{U0}} 1{D{U1}} 1{D{U2}} 1{D{U3}} 9{U} \\
    \textbf{first\_ch}       & 1{L} 1{H} 12{L} \\
    \textbf{last\_ch}        & 4{L} 1{H} 9{L} \\
    \textbf{v\_trans\_valid} & 2{L} 4{H} 8{L} \\
    \textbf{mult\_valid}     & 3{L} 4{H} 7{L} \\
    \textbf{accum\_valid}    & 5{L} 1{H} 8{L} \\
    \textbf{out\_valid}      & 7{L} 1{H} 6{L} \\
    \textbf{y\_tile} (Output)& 7{U} 1{D{Y Tile}} 6{U} \\
\extracode
    \vertlines[help lines, color=gray!40]{1,2,3,4,5,6,7,8,9,10,11,12,13,14}
    \node[above, font=\footnotesize\bfseries] at (1.5, 2.5) {T1};
    \node[above, font=\footnotesize\bfseries] at (2.5, 2.5) {T2};
    \node[above, font=\footnotesize\bfseries] at (3.5, 2.5) {T3};
    \node[above, font=\footnotesize\bfseries] at (4.5, 2.5) {T4};
    \node[above, font=\footnotesize\bfseries] at (5.5, 2.5) {T5};
    \node[above, font=\footnotesize\bfseries] at (6.5, 2.5) {T6};
    \node[above, font=\footnotesize\bfseries] at (7.5, 2.5) {T7};
    \draw[<->, >=Stealth, thick, blue!80!black] (1, -13.5) -- node[below, font=\small\bfseries] {Pipeline Latency = 5 Cycles} (6, -13.5);
\end{tikztimingtable}
\end{document}
"""

diagrams = [
    ("winograd_block_diagram", diagram_top_tex),
    ("input_transform_2d", diagram_in_trans_tex),
    ("output_transform_2d", diagram_out_trans_tex),
    ("winograd_fsm", diagram_fsm_tex),
    ("verification_flow", diagram_verif_tex),
    ("pipeline_timing", diagram_timing_tex)
]

for name, tex_code in diagrams:
    tex_path = os.path.join(IMG_DIR, f"{name}.tex")
    pdf_path = os.path.join(IMG_DIR, f"{name}.pdf")
    png_path = os.path.join(IMG_DIR, f"{name}.png")
    
    with open(tex_path, "w", encoding="utf-8") as f:
        f.write(tex_code)
    
    print(f"Compiling {name}.tex...")
    res = subprocess.run(
        ["pdflatex", "-interaction=nonstopmode", f"{name}.tex"],
        cwd=IMG_DIR,
        capture_output=True,
        text=True
    )
    if res.returncode != 0:
        print(f"Error compiling {name}.tex:\n{res.stderr}\n{res.stdout[-500:]}")
    else:
        print(f"Successfully generated {pdf_path}")
        # Convert to PNG using pdftoppm
        conv_res = subprocess.run(
            ["pdftoppm", "-png", "-r", "300", f"{name}.pdf", name],
            cwd=IMG_DIR,
            capture_output=True,
            text=True
        )
        # pdftoppm names it name-1.png or name.png
        gen_png = os.path.join(IMG_DIR, f"{name}-1.png")
        if os.path.exists(gen_png):
            if os.path.exists(png_path):
                os.remove(png_path)
            os.rename(gen_png, png_path)
            print(f"Successfully generated {png_path}")
        elif os.path.exists(os.path.join(IMG_DIR, f"{name}.png")):
            print(f"Successfully generated {png_path}")
        else:
            print(f"pdftoppm output: {conv_res.stdout} {conv_res.stderr}")

print("All diagrams processed!")
