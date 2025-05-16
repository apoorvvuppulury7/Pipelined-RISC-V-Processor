# Computer-Architecture-Project
Problem Statement

Design a 5-stage pipeline RISC processor (with hazard detection and data forwarding unit as necessary) that can execute the following instructions:

0000 SW    reg1, 7(reg2)  
0004 NOR   reg3, reg4, reg5  
0008 ADDI  reg6, reg3, 1078  
0012 AND   reg8, reg7, reg6  
0016 OR    reg9, reg8, reg3  

Initialize the register file with the following data:
reg1 = 90966

reg2 = 5
reg4 = FE331
reg5 = 45432
reg7 = 23211

Opcode for each instruction:
Instruction 1: 0000
Instruction 2: 0001
Instruction 3: 0011
Instruction 4: 0111
Instruction 5: 1111

The processor has the following control signals:
ALUSrc – Select the second input of ALU
ALUOp (2 bits) – Control ALU operation
MR – Read data from memory
MW – Write data into memory
MReg – Move data from memory to register
EnIM – Read instruction memory contents
EnRW – Write data into the register file
FA – Forward A mux control (used in data forwarding circuitry)
FB – Forward B mux control (used in data forwarding circuitry)
IFIDWrite – Disable IF/ID change (used in hazard detection circuit)
PCWrite – Disable PC change (used in hazard detection circuit)
ST – Control signal of mux which changes all control signals to zero (used in hazard detection circuit)

Other specifications:
Initialize PC with all zeros. Instruction memory size = 32 bytes. Processor has 16 registers, named reg0 to reg15, each 32 bits wide. A read from instruction memory outputs 4 consecutive bytes starting from the given byte address at the positive edge of the clock, if EnIM is high. The register file has:
Two 32-bit read ports: RD1 and RD2
One 32-bit write port: WD

At rising edge of the clock: RD1 and RD2 output data from registers addressed by RN1 and RN2. At falling edge of the clock: data is written via WD to the register at WN, if EnRW is true. Data memory size should be designed as per requirement. All data are in hexadecimal unless stated otherwise.

Design Requirements:
Create behavioral Verilog models for each architectural block. Build a top-level structural model of the processor by instantiating and interconnecting the blocks. Specify the size and format of all pipeline registers, including fields for:
Decoded control signals
Data
Show all input, output, and control signal waveforms in the report.

