module spi_peripheral (
    input  logic        clk,
    input  logic        rst,       
    input  logic        nCS,        
    input  logic        SCLK,      
    input  logic        COPI,       
    output logic [7:0]  uo_out      
);

    localparam  int MAX_ADDR = 5;

    logic [7:0] regs [0:MAX_ADDR-1]; //5 registers, 8 bits ea

    logic [15:0] shift_reg; //Holds incoming bits
    logic [3:0]  bit_cnt; //bits received count (2^4 = 16 max)

    // Synchronizers (2-stage)
    logic [1:0] sclk_sync, ncs_sync, copi_sync;

    // Synced signals
    logic SCLK_sync, SCLK_prev;
    logic nCS_sync, nCS_prev;
    logic COPI_sync;

    // Edge detection
    wire sclk_rise = (SCLK_prev == 0) && (SCLK_sync == 1);
    wire nCS_fall  = (nCS_prev == 1) && (nCS_sync == 0);
    wire nCS_rise  = (nCS_prev == 0) && (nCS_sync == 1);

    
    // Synchronize asynchronous inputs
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            sclk_sync <= 2'b00;
            ncs_sync  <= 2'b11; // idle = high
            copi_sync <= 2'b00;
        end else begin
            sclk_sync <= {sclk_sync[0], SCLK};
            ncs_sync  <= {ncs_sync[0],  nCS};
            copi_sync <= {copi_sync[0], COPI};
        end
    end

    // Assign synchronized versions
    assign SCLK_sync = sclk_sync[1];
    assign nCS_sync  = ncs_sync[1];
    assign COPI_sync = copi_sync[1];

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin //Reset everyting to 0
            shift_reg <= 16'b0;
            bit_cnt   <= 4'b0;
            uo_out    <= 8'b0;
            SCLK_prev <= 1'b0;
            nCS_prev  <= 1'b1;

            for (int i = 0; i < MAX_ADDR; i++) begin //Loop thrugh registers to reset them
                regs[i] <= 8'b0;
            end

        end else begin
            // Save previous values for edge detection
            SCLK_prev <= SCLK_sync;
            nCS_prev  <= nCS_sync;

            // Only capture when chip selected
            if (~nCS_sync && sclk_rise) begin //Active when low and rising
                shift_reg <= {shift_reg[14:0], COPI_sync}; //Drop oldest bit (MSB) and shift the rest left
                bit_cnt   <= bit_cnt + 1; //Increment counter
            end

            // On end of transaction
            if (nCS_rise && (bit_cnt == 16)) begin
                logic [0] rw = shift_reg[15]; // RW bit
                logic [6:0] addr = shift_reg[14:8]; //Take the address
                logic [7:0] data = shift_reg[7:0]; //Take the data

                if (addr < MAX_ADDR) begin //If address is valid, write in corresponding register
                    regs[addr] <= data;
                    if (addr == 0) uo_out <= data; //If address is 0, also update uo_out
                end

                // Reset bit counter after transaction
                bit_cnt <= 0;
            end
        end
    end

endmodule