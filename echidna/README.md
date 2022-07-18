# Instructions to setup and run ECHIDNA tests of ClaimFeeMaker

## Pre-requisites

- Clone the claim-fee-maker repository 

 `git clone git@github.com:deco-protocol/claim-fee-maker.git`
 
- Install Docker 

Follow instructions based on your Operating System : https://docs.docker.com/get-docker/ 


## Setup ECHIDNA

### Step 1 : Pull the Trail-Of-Bits ETH Sec ToolBox container image

- Pull the docker image

`docker pull trailofbits/eth-security-toolbox`

- Change to claim-fee-maker directory

`cd .../claim-fee-maker`

### Step 2 : Run the Trail-Of-Bits container 

`docker run -it -v "$PWD":/home/training trailofbits/eth-security-toolbox`

Note : Make sure you run this command when your pwd is set to cloned repo folder(i.e claim-fee-maker). This will enable you to access all the files and filders in the current working directory inside the container under `/home/training` folder.

Yay !! Setup is complete 

## Run ECHIDNA tests

The echidna tests of claimfee-maker are classified into 3 groups : 

1. Access Control Invariant Tests
2. Conditional Invariant Tests
3. Functional Invariant Tests

The Access Control invariants are aimed to test access modifiers or access controls held by different personas that interacts with claimfee-maker. These tests focus on the access modifiers : auth, afterClose, beforeClose.

The Conditional Invariants are held true based on prerequisites committed against business and logical state machines presented in the smart contract. These tests focus on "require" conditions to be met to execute the business logic. 

The Functional Invariants are held true based on the logical state machine and overall state presented in the claimfee-maker smart contract. 

### How To run Access Control Tests

`make echidna-claimfee-access`

### How to run Conditional Tests

`make echidna-claimfee-conditional`

### How to run Functional Invariant Tests

`make echidna-claimfee-functional`

The corpus will be collected in 'claim-fee-maker/corpus folder'. The corpus is collection of seed input, random inputs, coverage and execution flow of the target contract being tested.








