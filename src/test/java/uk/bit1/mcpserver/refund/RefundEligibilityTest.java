package uk.bit1.mcpserver.refund;

import static org.junit.jupiter.api.Assertions.assertEquals;

import java.time.Clock;
import java.time.Instant;
import java.time.ZoneOffset;
import java.util.List;
import java.util.Optional;
import org.junit.jupiter.api.Disabled;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;

/**
 * Test list for the refund eligibility check (src/refund-eligibility-example-mapping.md).
 *
 * <p>Fixture: now = 2026-11-08T12:00:00Z, so cutoff = 2026-10-09T12:00:00Z.
 *
 * <p>Customers: C1 active/normal, C2 active/watch, C3 active/blocked, C4 suspended/normal, C5
 * suspended/blocked.
 *
 * <p>Base order O1: customer C1, status delivered, delivered_at 2026-11-01T10:00:00Z, total_minor
 * 4999, currency GBP, refunded_at null. Each test varies only what its description names.
 *
 * <p>An ineligible result carries a verdict and reason, and no amount and no currency.
 */
class RefundEligibilityTest {

  private static final Instant NOW = Instant.parse("2026-11-08T12:00:00Z");

  private static final Customer C1 =
      new Customer("C1", "Alice", "alice@example.com", "active", "normal");

  private static final CustomerOrder O1 =
      new CustomerOrder(
          "O1",
          "C1",
          Instant.parse("2026-10-28T09:00:00Z"),
          Instant.parse("2026-11-01T10:00:00Z"),
          "delivered",
          4999,
          "GBP",
          null);

  private static RefundEligibilityCheck eligibilityCheck(
      List<Customer> customers, List<CustomerOrder> orders) {
    return new RefundEligibilityCheck(
        id -> customers.stream().filter(customer -> customer.id().equals(id)).findFirst(),
        id -> orders.stream().filter(order -> order.id().equals(id)).findFirst(),
        Clock.fixed(NOW, ZoneOffset.UTC));
  }

  // --- Regel 5: eligible result -------------------------------------------------------------

  @Test
  void eligibleOrderIsRefundableInFull() {
    RefundDecision decision = eligibilityCheck(List.of(C1), List.of(O1)).check("C1", "O1");

    assertEquals(
        new RefundDecision(
            true,
            "Order was delivered within the refund window and has no previous refund.",
            Optional.of(new RefundAmount(4999, "GBP"))),
        decision);
  }

  @Disabled("TODO: C1 + O1 with total_minor 12000, currency EUR -> eligible, amount 12000 EUR")
  @Test
  void refundableAmountIsTheOrderTotalInItsOriginalCurrency() {
    // Add the observation when this behavior enters Red.
  }

  // --- Regel 1: category A, identification --------------------------------------------------

  @Disabled(
      "TODO: A1 customer null, order O1 -> ineligible, 'Customer and order are required.', no"
          + " amount")
  @Test
  void customerIsRequired() {
    // Add the observation when this behavior enters Red.
  }

  @Disabled(
      "TODO: A1 customer C1, order null -> ineligible, 'Customer and order are required.', no"
          + " amount")
  @Test
  void orderIsRequired() {
    // Add the observation when this behavior enters Red.
  }

  @Disabled("TODO: A2 customer C99, order O1 -> ineligible, 'Customer was not found.', no amount")
  @Test
  void customerMustExist() {
    // Add the observation when this behavior enters Red.
  }

  @Disabled("TODO: A3 customer C1, order O99 -> ineligible, 'Order was not found.', no amount")
  @Test
  void orderMustExist() {
    // Add the observation when this behavior enters Red.
  }

  @Disabled(
      "TODO: Regel 0 (A2 before A3) customer C99, order O-unknown -> ineligible, 'Customer was not"
          + " found.'")
  @Test
  void unknownCustomerIsReportedBeforeUnknownOrder() {
    // Add the observation when this behavior enters Red.
  }

  @Disabled(
      "TODO: A4 customer C1, order O1 placed by C2 -> ineligible, 'Order does not belong to the"
          + " selected customer.', no amount")
  @Test
  void orderMustBelongToTheCustomer() {
    // Add the observation when this behavior enters Red.
  }

  // --- Regel 2: category B, customer standing -----------------------------------------------

  @Disabled(
      "TODO: B1 customer C4 (suspended) with own delivered order -> ineligible, 'Customer is not"
          + " active.', no amount")
  @Test
  void customerMustBeActive() {
    // Add the observation when this behavior enters Red.
  }

  @Disabled(
      "TODO: B2 customer C3 (blocked) with own delivered order -> ineligible, 'Customer risk level"
          + " blocks this refund.', no amount")
  @Test
  void customerMustNotBeBlocked() {
    // Add the observation when this behavior enters Red.
  }

  @Disabled(
      "TODO: Regel 0 (B1 before B2) customer C5 (suspended AND blocked) with own delivered order ->"
          + " ineligible, 'Customer is not active.'")
  @Test
  void inactiveIsReportedBeforeBlocked() {
    // Add the observation when this behavior enters Red.
  }

  // --- Regel 3: category C, order state -----------------------------------------------------

  @Disabled(
      "TODO: C1 O1 with refunded_at 2026-11-02T09:00:00Z -> ineligible, 'Order has already been"
          + " refunded.', no amount")
  @Test
  void orderMustNotAlreadyBeRefunded() {
    // Add the observation when this behavior enters Red.
  }

  @Disabled(
      "TODO: C2 O1 with status in_transit -> ineligible, 'Order must be delivered before a refund"
          + " can be considered.', no amount")
  @Test
  void orderMustBeDelivered() {
    // Add the observation when this behavior enters Red.
  }

  @Disabled(
      "TODO: Regel 0 (C1 before C2) O1 with refunded_at set AND status pending -> ineligible,"
          + " 'Order has already been refunded.'")
  @Test
  void existingRefundIsReportedBeforeNotDelivered() {
    // Add the observation when this behavior enters Red.
  }

  @Disabled(
      "TODO: C3 O1 with status delivered, delivered_at null -> ineligible, 'Order has no recorded"
          + " delivery date.', no amount")
  @Test
  void deliveryDateMustBeKnown() {
    // Add the observation when this behavior enters Red.
  }

  // --- Regel 4: category D, refund window ---------------------------------------------------

  @Disabled(
      "TODO: D1 O1 delivered 2026-08-01T10:00:00Z -> ineligible, 'Order was delivered outside the"
          + " refund window.', no amount")
  @Test
  void orderDeliveredLongAgoIsOutsideTheWindow() {
    // Add the observation when this behavior enters Red.
  }

  @Disabled(
      "TODO: D1 O1 delivered 2026-10-09T11:59:59Z (1 s before cutoff) -> ineligible, 'Order was"
          + " delivered outside the refund window.'")
  @Test
  void orderDeliveredJustBeforeTheCutoffIsOutsideTheWindow() {
    // Add the observation when this behavior enters Red.
  }

  @Disabled(
      "TODO: D1 O1 delivered 2026-10-09T12:00:00Z (exactly at cutoff) -> eligible, amount 4999"
          + " GBP")
  @Test
  void orderDeliveredExactlyAtTheCutoffIsInsideTheWindow() {
    // Add the observation when this behavior enters Red.
  }

  @Disabled(
      "TODO: Regel 0 (B before D) customer C3 (blocked), own order delivered 2026-08-01T10:00:00Z"
          + " -> ineligible, 'Customer risk level blocks this refund.'")
  @Test
  void blockedIsReportedBeforeOutsideTheWindow() {
    // Add the observation when this behavior enters Red.
  }

  @Nested
  class Verification {

    @Disabled("TODO: C1 O1 with total_minor 0 -> eligible, amount 0 GBP")
    @Test
    void zeroTotalOrderIsEligibleForZero() {
      // Add the observation when this test is activated.
    }

    @Disabled(
        "TODO: A1 only null counts as missing: customer \"\", order O1 -> ineligible, 'Customer was"
            + " not found.'")
    @Test
    void emptyCustomerIdIsNotFoundRatherThanMissing() {
      // Add the observation when this test is activated.
    }

    @Disabled(
        "TODO: B1 exact match: customer status 'Active', risk normal -> ineligible, 'Customer is"
            + " not active.'")
    @Test
    void capitalisedActiveStatusIsNotActive() {
      // Add the observation when this test is activated.
    }

    @Disabled("TODO: B2 customer C2 (watch) with own delivered order -> eligible, amount 4999 GBP")
    @Test
    void watchListCustomerIsPlainEligible() {
      // Add the observation when this test is activated.
    }

    @Disabled(
        "TODO: B2 active customer with risk_level 'high', own delivered order -> eligible, amount"
            + " 4999 GBP")
    @Test
    void unknownRiskLevelDoesNotBlock() {
      // Add the observation when this test is activated.
    }

    @Disabled(
        "TODO: B2 active customer with risk_level null, own delivered order -> eligible, amount"
            + " 4999 GBP")
    @Test
    void missingRiskLevelDoesNotBlock() {
      // Add the observation when this test is activated.
    }

    @Disabled(
        "TODO: C1/C2 O1 with status refunded, refunded_at null -> ineligible, 'Order must be"
            + " delivered before a refund can be considered.'")
    @Test
    void refundedStatusWithoutRefundDateIsReportedAsNotDelivered() {
      // Add the observation when this test is activated.
    }

    @Disabled(
        "TODO: D1 O1 delivered 2026-11-09T12:00:00Z (in the future) -> eligible, amount 4999 GBP")
    @Test
    void futureDeliveryDateIsInsideTheWindow() {
      // Add the observation when this test is activated.
    }

    @Disabled(
        "TODO: Regel 0 (A before B) customer C4 (suspended), order placed by C2 -> ineligible,"
            + " 'Order does not belong to the selected customer.'")
    @Test
    void ownershipIsReportedBeforeInactive() {
      // Add the observation when this test is activated.
    }

    @Disabled(
        "TODO: Regel 0 (B before C) customer C3 (blocked), own order already refunded ->"
            + " ineligible, 'Customer risk level blocks this refund.'")
    @Test
    void blockedIsReportedBeforeAlreadyRefunded() {
      // Add the observation when this test is activated.
    }

    @Disabled(
        "TODO: Regel 0 (C before D) O1 already refunded and delivered 2026-08-01T10:00:00Z ->"
            + " ineligible, 'Order has already been refunded.'")
    @Test
    void alreadyRefundedIsReportedBeforeOutsideTheWindow() {
      // Add the observation when this test is activated.
    }
  }
}
