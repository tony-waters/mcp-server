package uk.bit1.mcpserver.refund;

import java.util.Optional;

public record RefundDecision(
    boolean eligible, String reason, Optional<RefundAmount> refundableAmount) {}
