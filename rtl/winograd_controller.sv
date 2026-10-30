// =============================================================================
// Module: winograd_controller
// Description: Finite State Machine controlling handshakes and multi-channel steps
// =============================================================================
`timescale 1ns / 1ps

module winograd_controller (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        start,
    input  logic [7:0]  cin_count,
    input  logic        pipe_busy,

    output logic        ready,
    output logic        first_channel,
    output logic        last_channel,
    output logic        channel_valid,
    output logic [7:0]  current_channel,
    output logic        tile_done
);

    typedef enum logic [1:0] {
        IDLE        = 2'b00,
        PROCESS     = 2'b01,
        WAIT_DRAIN  = 2'b10,
        DONE        = 2'b11
    } state_t;

    state_t state, next_state;
    logic [7:0] ch_cnt;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state   <= IDLE;
            ch_cnt  <= 8'd0;
        end else begin
            state <= next_state;
            if (state == IDLE && start) begin
                ch_cnt <= 8'd0;
            end else if (state == PROCESS) begin
                if (ch_cnt == cin_count - 1) begin
                    ch_cnt <= 8'd0;
                end else begin
                    ch_cnt <= ch_cnt + 1'b1;
                end
            end
        end
    end

    always_comb begin
        next_state    = state;
        ready         = 1'b0;
        first_channel = (ch_cnt == 8'd0);
        last_channel  = (ch_cnt == cin_count - 1);
        channel_valid = 1'b0;
        tile_done     = 1'b0;

        case (state)
            IDLE: begin
                ready = 1'b1;
                if (start) begin
                    next_state = PROCESS;
                end
            end

            PROCESS: begin
                channel_valid = 1'b1;
                if (last_channel) begin
                    next_state = WAIT_DRAIN;
                end
            end

            WAIT_DRAIN: begin
                if (!pipe_busy) begin
                    next_state = DONE;
                end
            end

            DONE: begin
                tile_done  = 1'b1;
                next_state = IDLE;
            end
        endcase
    end

    assign current_channel = ch_cnt;

endmodule
