# AXI4-Lite to APB Bridge with Asynchronous CDC

This project implements a robust bridge between an **AXI4-Lite** master (fast clock domain) and an **APB** slave (slow clock domain). It features asynchronous FIFOs for safe Clock Domain Crossing (CDC) and a fully verifiable testbench.

## 1. System Data & Control Flow

This diagram illustrates how data flows from the AXI Master, through the CDC FIFOs, to the APB FSM, and back.

```mermaid
graph LR
    %% Styles
    classDef aclk fill:#e1f5fe,stroke:#01579b,stroke-width:2px,color:black;
    classDef pclk fill:#fff3e0,stroke:#e65100,stroke-width:2px,color:black;
    classDef fifo fill:#e8f5e9,stroke:#2e7d32,stroke-width:2px,stroke-dasharray: 5 5,color:black;
    classDef ext fill:#f5f5f5,stroke:#616161,stroke-width:1px,color:black;

    %% External Interfaces
    AXI_Master["AXI4-Lite Master<br/>(Testbench)"]:::ext
    APB_Slaves["APB Slaves<br/>(External / TB)"]:::ext

    %% ACLK Domain Subgraph
    subgraph ACLK_Domain [ACLK Domain]
        direction TB
        AXI_Slave["AXI Lite Slave FSM<br/>(axi_lite_slave.sv)"]:::aclk
    end

    %% PCLK Domain Subgraph
    subgraph PCLK_Domain [PCLK Domain]
        direction TB
        Arbiter["Arbiter Logic<br/>(axi_apb_bridge_top.sv)"]:::pclk
        APB_FSM["APB Master FSM<br/>(apb_master_fsm.sv)"]:::pclk
    end

    %% FIFOs (CDC)
    subgraph CDC [Clock Domain Crossing]
        WrCmd_FIFO(("Write Cmd FIFO<br/>(async_fifo.sv)")):::fifo
        RdCmd_FIFO(("Read Cmd FIFO<br/>(async_fifo.sv)")):::fifo
        WrRsp_FIFO(("Write Rsp FIFO<br/>(async_fifo.sv)")):::fifo
        RdRsp_FIFO(("Read Rsp FIFO<br/>(async_fifo.sv)")):::fifo
    end

    %% Flow Connections - Write Path
    AXI_Master -- AW, W --> AXI_Slave
    AXI_Slave -- Push Cmd --> WrCmd_FIFO
    WrCmd_FIFO -- Pop Cmd --> Arbiter
    Arbiter --> APB_FSM
    APB_FSM -- PADDR, PWDATA --> APB_Slaves
    
    %% Response Path
    APB_Slaves -- PREADY, PSLVERR, PRDATA --> APB_FSM
    APB_FSM -- Push Resp --> WrRsp_FIFO
    WrRsp_FIFO -- Pop Resp --> AXI_Slave
    AXI_Slave -- BRESP --> AXI_Master

    %% Flow Connections - Read Path
    AXI_Master -- AR --> AXI_Slave
    AXI_Slave -- Push Cmd --> RdCmd_FIFO
    RdCmd_FIFO -- Pop Cmd --> Arbiter
    Arbiter -.-> APB_FSM
    APB_FSM -- PRDATA --> RdRsp_FIFO
    RdRsp_FIFO -- Pop Data --> AXI_Slave
    AXI_Slave -- RDATA, RRESP --> AXI_Master
```

## 2. AXI4-Lite Handshake Diagram (Slave Side)

The bridge acts as an **AXI Slave**. It accepts address and data from the master and provides responses.

```mermaid
graph LR
    subgraph Master_Side ["AXI Master (Testbench / CPU)"]
        direction TB
    end

    subgraph Slave_Side ["Bridge (AXI Slave)"]
        direction TB
    end

    %% Write Address Channel
    Master_Side -- "AWADDR, AWVALID" --> Slave_Side
    Slave_Side -. "AWREADY" .-> Master_Side

    %% Write Data Channel
    Master_Side -- "WDATA, WSTRB, WVALID" --> Slave_Side
    Slave_Side -. "WREADY" .-> Master_Side

    %% Write Response Channel
    Slave_Side -- "BRESP, BVALID" --> Master_Side
    Master_Side -. "BREADY" .-> Slave_Side

    %% Read Address Channel
    Master_Side -- "ARADDR, ARVALID" --> Slave_Side
    Slave_Side -. "ARREADY" .-> Master_Side

    %% Read Data Channel
    Slave_Side -- "RDATA, RRESP, RVALID" --> Master_Side
    Master_Side -. "RREADY" .-> Slave_Side
```

## 3. APB Handshake Diagram (Master Side)

The bridge acts as an **APB Master**. It drives controls to the peripheral and waits for `PREADY`.

```mermaid
graph LR
    %% Styles
    classDef master fill:#e1f5fe,stroke:#01579b,stroke-width:2px;
    classDef bridge fill:#fff9c4,stroke:#fbc02d,stroke-width:2px;
    classDef slave fill:#e8f5e9,stroke:#2e7d32,stroke-width:2px;

    %% Nodes
    AXI_M("AXI4-Lite Master"):::master
    BRIDGE("AXI-to-APB Bridge"):::bridge
    APB_S("APB Slave"):::slave

    %% -- Forward Path (Command) --
    AXI_M -- "AWADDR, WDATA, WVALID" --> BRIDGE
    BRIDGE -. "AWREADY, WREADY" .-> AXI_M
    
    BRIDGE -- "PSEL, PENABLE, PADDR" --> APB_S
    BRIDGE -- "PWDATA, PWRITE=1" --> APB_S

    %% -- Return Path (Response) --
    APB_S -. "PREADY" .-> BRIDGE
    BRIDGE -- "BRESP, BVALID" --> AXI_M
    AXI_M -. "BREADY" .-> BRIDGE
```
