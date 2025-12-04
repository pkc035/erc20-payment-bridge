````markdown
# DavenAIPaymentBridge

`DavenAIPaymentBridge`는 **CC 토큰으로 결제를 받고**, 미리 예치된 **CBK 토큰**을 고정 비율로 환산해 **지급용 지갑(payoutWallet)** 으로 전송하는 **ERC-20 기반 결제 브릿지 스마트 컨트랙트**입니다.

온체인에서는 토큰 송금 및 이벤트 로깅만 담당하고,  
유저/상품 식별자(`userId`, `productId`)는 오프체인 시스템(DB/백엔드)과 연동하는 방식으로 설계되어 있습니다.

---

## 주요 개념

- **CC 토큰 (ccToken)**  
  유저가 결제에 사용하는 ERC-20 토큰

- **CBK 토큰 (cbkToken)**  
  회사(또는 서비스 제공자)가 지급/정산에 사용하는 ERC-20 토큰  
  컨트랙트에 미리 예치해 두고, 유저 결제 시 `payoutWallet`으로 전송됩니다.

- **payoutWallet**  
  실제로 CBK 토큰을 전달받는 지갑 주소 (사업자/회사 지갑 등)

- **고정 환율 (CC_TO_CBK_RATE)**  
  ```solidity
  uint256 public constant CC_TO_CBK_RATE = 1000;
````

* `cbkAmount = ccAmount / 1000` (Solidity 정수 나눗셈)
* 예) `ccAmount = 10_000` → `cbkAmount = 10`

---

## 컨트랙트 개요

```solidity
contract DavenAIPaymentBridge {
    address public owner;                 
    address public payoutWallet;          

    IERC20 public immutable ccToken;      
    IERC20 public immutable cbkToken;    

    uint256 public constant CC_TO_CBK_RATE = 1000;

    ...
}
```

* `owner`

  * 컨트랙트 관리자 주소
  * 특정 함수(`onlyOwner`) 호출 가능
* `payoutWallet`

  * 유저 결제 시 CBK 토큰이 전송되는 최종 지갑
* `ccToken`, `cbkToken`

  * 각각 결제용/지급용 ERC-20 토큰 컨트랙트 주소 (배포 시 지정, 변경 불가)

---

## 주요 기능

### 1. Ownership 관리

```solidity
function transferOwnership(address newOwner) external onlyOwner;
```

* 컨트랙트 소유자 변경
* `newOwner != address(0)` 검증
* `OwnershipTransferred` 이벤트 발생

---

### 2. 지급 지갑 설정

```solidity
function setPayoutWallet(address _newWallet) external onlyOwner;
```

* CBK 토큰이 실제로 들어갈 `payoutWallet` 설정/변경
* `payoutWallet == address(0)` 인 경우 유저 결제 함수 사용 불가
* `PayoutWalletUpdated` 이벤트 발생

---

### 3. CBK 금고(Vault) 예치

```solidity
function depositCbkToVault(uint256 amount) external onlyOwner;
```

* 오너가 컨트랙트에 CBK 토큰을 예치하는 함수
* 순서:

  1. 오너가 `cbkToken.approve(bridgeAddress, amount)` 호출
  2. `depositCbkToVault(amount)` 호출 → `transferFrom(owner → contract)` 수행
* 예치된 CBK는 나중에 유저 결제 시 `payoutWallet`으로 출금됨

---

### 4. 토큰 출금(Owner 용)

```solidity
function withdrawToken(address tokenAddress, uint256 amount) external onlyOwner;
```

* 컨트랙트에 보관 중인 **임의의 ERC-20 토큰**을 오너가 회수
* CC/CBK는 물론, 실수로 전송된 다른 토큰도 회수 가능

> ⚠️ 오너는 이 함수를 통해 **컨트랙트 내 모든 토큰을 인출**할 수 있으므로,
> 이 컨트랙트는 **오너를 신뢰하는 중앙화 모델**임을 전제로 합니다.

---

### 5. 유저 결제: `depositCcAndSendCbk`

```solidity
function depositCcAndSendCbk(
    uint256 ccAmount,
    uint256 userId,
    uint256 productId
) external;
```

유저가 실제로 호출하는 결제 함수입니다.

#### 동작 흐름

1. 유저가 먼저 CC 토큰 승인:

   ```solidity
   ccToken.approve(bridgeAddress, ccAmount);
   ```

2. 유저가 `depositCcAndSendCbk(ccAmount, userId, productId)` 호출

3. 컨트랙트 내부 로직:

   * `ccAmount > 0` 확인
   * `payoutWallet` 설정 여부 확인
   * `allowance` 확인 (`ccToken.allowance(msg.sender, address(this))`)
   * `ccToken.transferFrom(msg.sender → contract)`
   * `cbkAmount = ccAmount / CC_TO_CBK_RATE`
   * 컨트랙트 보유 CBK 잔고 확인
   * `cbkToken.transfer(contract → payoutWallet, cbkAmount)`
   * `PaymentCompleted` 이벤트 발생

#### 이벤트

```solidity
event PaymentCompleted(
    address indexed from,
    uint256 ccAmount,
    uint256 cbkAmount,
    uint256 indexed userId,
    uint256 indexed productId
);
```

* `from`      : 결제한 유저 주소
* `ccAmount`  : 유저가 전송한 CC 토큰 수량
* `cbkAmount` : 환산되어 `payoutWallet`로 전송된 CBK 수량
* `userId`    : 오프체인 유저 식별용 ID
* `productId` : 오프체인 상품/서비스 식별용 ID

백엔드/인덱서에서 이 이벤트를 구독해
**온체인 결제 내역 ↔ 오프체인 유저/상품 정보**를 매핑할 수 있습니다.

---

## 사용 예시 플로우

### 1. 배포 (Owner)

```solidity
DavenAIPaymentBridge bridge = new DavenAIPaymentBridge(
    ccTokenAddress,
    cbkTokenAddress
);
```

### 2. 초기 설정 (Owner)

```solidity
// payoutWallet 설정
bridge.setPayoutWallet(payoutWalletAddress);

// CBK 토큰 Vault에 예치
cbkToken.approve(address(bridge), cbkAmount);
bridge.depositCbkToVault(cbkAmount);
```

### 3. 유저 결제 (User)

```solidity
// 1) CC 토큰 사용 승인
ccToken.approve(address(bridge), ccAmount);

// 2) 결제 요청
bridge.depositCcAndSendCbk(
    ccAmount,
    userId,     // 백엔드 유저 ID
    productId   // 상품/서비스 ID
);
```

---

## Security Considerations (보안 관련 주의사항)

> ⚠ **본 컨트랙트는 “완전 신뢰 기반(owner-trusted)” 구조입니다.**
> 온체인에서 완전히 탈중앙화된 결제/브릿지를 기대하는 용도에는 적합하지 않을 수 있습니다.

### 1. 중앙화/Trust 모델

* `owner`는 `withdrawToken`을 통해 **컨트랙트 내 모든 토큰을 회수**할 수 있습니다.
* 따라서,

  * 유저/파트너는 이 컨트랙트를 사용할 때 **owner(회사/운영 주체)를 신뢰**해야 합니다.
  * 운영 환경에서는 **멀티시그 지갑**, **타임락**, **온체인 거버넌스**와 함께 사용하는 것을 권장합니다.

### 2. 토큰 주소 설정

* 현재 구현에서는 생성자에서 토큰 주소에 대한 별도 검증(0주소, 동일 주소 등)이 없습니다.
* 실제 프로덕션 배포 시에는 다음과 같은 검증을 추가하는 것을 고려할 수 있습니다:

  ```solidity
  require(_ccTokenAddress != address(0) && _cbkTokenAddress != address(0), "Invalid token");
  require(_ccTokenAddress != _cbkTokenAddress, "Tokens must differ");
  ```

### 3. ERC-20 호환성

* 인터페이스는 `transfer`, `transferFrom` 이 `bool`을 반환하는 **표준 ERC-20**을 가정합니다.
* 일부 비표준 토큰(예: 옛날 USDT 등)과는 호환되지 않을 수 있습니다.
* 안정성을 높이기 위해 운영 시에는 OpenZeppelin의 `IERC20`, `SafeERC20` 사용을 고려할 수 있습니다.

### 4. Pause / Emergency 기능 없음

* 문제가 발생했을 때 컨트랙트를 일시적으로 정지시키는 `pause`/`unpause` 기능은 없습니다.
* 필요한 경우 다음과 같은 패턴을 추가해 운영 리스크를 줄일 수 있습니다:

  * `bool public paused;`
  * `modifier whenNotPaused` / `whenPaused`
  * Owner가 비상 상황에서 결제 기능을 잠시 중단할 수 있도록 설계

### 5. 감사(Audit)

* 본 컨트랙트는 구조가 단순하고 치명적인 취약점은 적어 보이지만,
  **실제 메인넷 대규모 자산**을 다루는 경우에는

  * 전문 보안 업체의 코드 감사(Security Audit),
  * 버그 바운티 프로그램,
  * 내부 코드 리뷰 프로세스
    등을 거치는 것을 강하게 권장합니다.

---

## License

```text
SPDX-License-Identifier: MIT
```

이 저장소의 코드는 MIT 라이선스를 따릅니다.
