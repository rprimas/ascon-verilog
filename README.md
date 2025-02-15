# Hardware Design of [Ascon-AEAD128](https://ascon.iaik.tugraz.at)

[Ascon](https://ascon.iaik.tugraz.at) is a family of authenticated encryption and hashing algorithms designed to be lightweight and easy to implement, even with added countermeasures against side-channel attacks. Ascon has been selected as new standard for lightweight cryptography in the [NIST Lightweight Cryptography competition](https://www.nist.gov/news-events/news/2023/02/nist-selects-lightweight-cryptography-algorithms-protect-small-devices) (2019–2023). The current draft standard of Ascon is available [here](https://nvlpubs.nist.gov/nistpubs/SpecialPublications/NIST.SP.800-232.ipd.pdf).

> [!NOTE]
> This is a work-in-progress hardware implementation of the Ascon family of lightweight cryptographic algorithms that is compatible with the current draft standard [NIST SP 800-232](https://csrc.nist.gov/pubs/sp/800/232/ipd).

## Available Variants

| **Variant** | **Modes**                    | **Bus Width** | **Unrolled Rounds** |
|-------------|------------------------------|--------------:|:-------------------:|
| v1          | Ascon-AEAD128, Ascon-Hash256 |        32-bit |          1          |
| v2          | Ascon-AEAD128, Ascon-Hash256 |        32-bit |          2          |
| v3          | Ascon-AEAD128, Ascon-Hash256 |        32-bit |          4          |
| v4          | Ascon-AEAD128, Ascon-Hash256 |        64-bit |          1          |
| v5          | Ascon-AEAD128, Ascon-Hash256 |        64-bit |          2          |
| v6          | Ascon-AEAD128, Ascon-Hash256 |        64-bit |          4          |

## Files

- `rtl/ascon_core.sv`: Verilog implementation of the Ascon core.
- `rtl/asconp.sv`: Verilog implementation of the Ascon permutation.
- `rtl/config_core.sv`: Configuration file for the Ascon core and test bench.
- `ascon.py`: Reference software implementation of Ascon, used by `test.py`.
- `LICENSE`: License file.
- `Makefile`: Commands for running [cocotb](https://www.cocotb.org/) verilator test bench.
- `README.md`: This README.
- `surfer.ron`: Configuration file for the [Surfer](https://surfer-project.org/) waveform viewer.
- `test.py`: Python script for running test bench, used by cocotb.

## Interface

The following table contains a description of the interface signals:

| **Name**   | **Bits** | **Description**                                     |
|------------|:--------:|-----------------------------------------------------|
| clk        |     1    | Clock signal.                                       |
| rst        |     1    | Reset signal. Note: Synchronous active high.        |
| key        |   32/64  | Key data input.                                     |
| key_valid  |     1    | Key data is valid.                                  |
| key_ready  |     1    | Ascon core is ready to receive a new key.           |
| bdi_data   |   32/64  | Block data input (BDI).                             |
| bdi_valid  |    4/8   | Valid BDI data bytes.                               |
| bdi_ready  |     1    | Ascon core is ready to receive data.                |
| bdi_eot    |     1    | Current BDI block is the last block of its type.    |
| bdi_eoi    |     1    | Current BDI block is the last block of input.       |
| bdi_type   |     4    | Type of BDI data.                                   |
| mode       |     4    | Ascon mode.                                         |
| bdo_data   |   32/64  | Block data output (BDO).                            |
| bdo_valid  |    4/8   | Valid BDO data bytes.                               |
| bdo_ready  |     1    | Test bench is ready to receive data.                |
| bdo_type   |     4    | Type of BDO data.                                   |
| auth       |     1    | 1=Authentication success, 0=Authentication failure. |
| auth_valid |     1    | Authentication output is valid.                     |

## Quick Start

- Install the Verilator open-source verilog simulator with **version >= 5.0**:
  - Ubuntu:
    - `apt-get install verilator`
  - Fedora:
    - `dnf install verilator`
    - `dnf install verilator-devel`
  - Build from source:
    - [Git Quick Install](https://verilator.org/guide/latest/install.html#git-quick-install)
- Install the [cocotb](https://www.cocotb.org/) open-source verilog test bench environment:
  - `pip install cocotb`
- Execute the cocotb test bench:
  - `make`

## View waveforms

- Install the [Surfer](https://surfer-project.org/) waveform viewer.
- View waveform of cocotb test bench run:
  - `make surf`
  
<img src="surfer.png" alt="Surfer waveform viewer" width="400"/>

## Contact

- Robert Primas (rprimas 'at' proton.me, https://rprimas.github.io)

## Acknowledgements

The interface of the Ascon core is inspired by the [LWC Hardware API Development Package](https://github.com/GMUCERG/LWC) that was mainly developed by the [Cryptographic Engineering Research Group](https://cryptography.gmu.edu) at George Mason University (GMU).
