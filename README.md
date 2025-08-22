# RISCV-Processors

This repository contains the processors made using Verilog as a part of the course CS F342 Computer Architecture at BITS Pilani, Hyderabad Campus

# [Single Cycle](https://github.com/abhishek2002228/RISCV-Processors/tree/main/Single_Cycle): 
*Supports the following instructions as of now*
                <ul>
                <li> *LW (I-type OPCODE: 0110011)* </li>
                <li> *SW (S-type OPCODE: 0100011)* </li>
                <li> *BEQ (B-type OPCODE: 1100011)* </li>
                <li> *The following R-type instructions (R-type OPCODE: 1100011):*</li>
                     <ul>
                       <li> *ADD (funct3: 000, funct7: 0000000)* </li>
                       <li> *SUB (funct3: 000, funct7: 0100000)* </li>
                       <li> *AND (funct3: 111, funct7: 0000000)* </li>
                       <li> *OR (funct3: 110, funct7: 0000000)* </li>
  </ul>
  </ul>
  
  
  The modules can be easily modified to add other instructions. That work is left for the future.


# [5 Stage Pipelined Processor](https://github.com/abhishek2002228/RISCV-Processors/tree/main/Pipelined%20RISCV%20Processor):

5 Stage pipelined processor with Forwarding Logic and Hazard Detection. Supports the same instructions as the Single Cycle Processor above.
The design supports the branch-not-taken branch prediction policy. The next step would be to implement a better branch predictor for the pipelined processor 

<img src="/Pipelined%20RISCV%20Processor/pipelined.png">
