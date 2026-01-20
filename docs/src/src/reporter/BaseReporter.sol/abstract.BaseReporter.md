# BaseReporter
[Git Source](https://github.com/SovaNetwork/fountfi/blob/a2137abe6629a13ef56e85f61ccb9fcfe0d3f27a/src/reporter/BaseReporter.sol)

Abstract base contract for reporters that return strategy info


## Functions
### report

Report the current value of an asset


```solidity
function report() external view virtual returns (bytes memory);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bytes`|the content of the report|


