package uk.bit1.mcpserver.refund;

import java.time.Clock;
import java.util.Optional;
import java.util.function.Function;

public class RefundEligibilityCheck {

  private final Function<String, Optional<Customer>> findCustomer;
  private final Function<String, Optional<CustomerOrder>> findOrder;
  private final Clock clock;

  public RefundEligibilityCheck(
      Function<String, Optional<Customer>> findCustomer,
      Function<String, Optional<CustomerOrder>> findOrder,
      Clock clock) {
    this.findCustomer = findCustomer;
    this.findOrder = findOrder;
    this.clock = clock;
  }

  public RefundDecision check(String customerId, String orderId) {
    return null;
  }
}
