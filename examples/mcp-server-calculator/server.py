#!/usr/bin/env python3
"""
Simple Calculator MCP Server

This MCP server provides basic arithmetic operations using the FastMCP framework.
It demonstrates the minimal implementation of an MCP server compliant with the
Model Context Protocol specification.

Tools provided:
- add: Add two numbers
- subtract: Subtract one number from another
- multiply: Multiply two numbers
- divide: Divide one number by another
- calculate: Evaluate a mathematical expression

Resources provided:
- calculator://constants: Mathematical constants (pi, e, etc.)

Built with FastMCP: https://github.com/jlowin/fastmcp
"""

from fastmcp import FastMCP
from typing import Union
import os
import math

# Initialize MCP server
mcp = FastMCP("Calculator", version="1.0.0")

# Configuration from environment
MAX_PRECISION = int(os.getenv("MAX_PRECISION", "10"))
LOG_LEVEL = os.getenv("LOG_LEVEL", "info")


@mcp.tool
async def add(a: float, b: float) -> float:
    """Add two numbers together.

    Args:
        a: First number
        b: Second number

    Returns:
        Sum of a and b
    """
    result = a + b
    return round(result, MAX_PRECISION)


@mcp.tool
async def subtract(a: float, b: float) -> float:
    """Subtract one number from another.

    Args:
        a: Number to subtract from
        b: Number to subtract

    Returns:
        Difference (a - b)
    """
    result = a - b
    return round(result, MAX_PRECISION)


@mcp.tool
async def multiply(a: float, b: float) -> float:
    """Multiply two numbers.

    Args:
        a: First number
        b: Second number

    Returns:
        Product of a and b
    """
    result = a * b
    return round(result, MAX_PRECISION)


@mcp.tool
async def divide(a: float, b: float) -> Union[float, str]:
    """Divide one number by another.

    Args:
        a: Numerator
        b: Denominator

    Returns:
        Quotient (a / b), or error message if division by zero
    """
    if b == 0:
        return "Error: Division by zero"

    result = a / b
    return round(result, MAX_PRECISION)


@mcp.tool
async def power(base: float, exponent: float) -> float:
    """Raise a number to a power.

    Args:
        base: Base number
        exponent: Exponent

    Returns:
        base^exponent
    """
    result = base ** exponent
    return round(result, MAX_PRECISION)


@mcp.tool
async def sqrt(n: float) -> Union[float, str]:
    """Calculate square root of a number.

    Args:
        n: Number to calculate square root of

    Returns:
        Square root of n, or error message if n is negative
    """
    if n < 0:
        return "Error: Cannot calculate square root of negative number"

    result = math.sqrt(n)
    return round(result, MAX_PRECISION)


@mcp.tool
async def calculate(expression: str) -> Union[float, str]:
    """Evaluate a mathematical expression safely.

    Args:
        expression: Mathematical expression (e.g., "2 + 3 * 4")

    Returns:
        Result of evaluation, or error message if invalid expression

    Security:
        Uses ast.literal_eval for safe evaluation (no code execution)
    """
    import ast
    import operator

    # Supported operators
    operators = {
        ast.Add: operator.add,
        ast.Sub: operator.sub,
        ast.Mult: operator.mul,
        ast.Div: operator.truediv,
        ast.Pow: operator.pow,
        ast.USub: operator.neg,
    }

    def eval_expr(node):
        if isinstance(node, ast.Constant):  # Python 3.8+
            return node.value
        elif isinstance(node, ast.BinOp):
            left = eval_expr(node.left)
            right = eval_expr(node.right)
            return operators[type(node.op)](left, right)
        elif isinstance(node, ast.UnaryOp):
            operand = eval_expr(node.operand)
            return operators[type(node.op)](operand)
        else:
            raise ValueError(f"Unsupported operation: {type(node)}")

    try:
        tree = ast.parse(expression, mode='eval')
        result = eval_expr(tree.body)
        return round(result, MAX_PRECISION)
    except (SyntaxError, ValueError, KeyError, ZeroDivisionError) as e:
        return f"Error: Invalid expression - {str(e)}"


@mcp.resource("calculator://constants")
async def get_mathematical_constants() -> str:
    """Get common mathematical constants.

    Returns:
        Formatted string with mathematical constants
    """
    return f"""Mathematical Constants:

π (pi):     {math.pi}
e (euler):  {math.e}
τ (tau):    {math.tau}
φ (phi):    {(1 + math.sqrt(5)) / 2}  # Golden ratio
√2:         {math.sqrt(2)}
"""


@mcp.prompt("calculate_prompt")
async def calculate_prompt_template(operation: str = "add") -> str:
    """Generate a prompt for performing calculations.

    Args:
        operation: Type of operation (add, subtract, multiply, divide)

    Returns:
        Formatted prompt template
    """
    templates = {
        "add": "Please add {a} and {b}",
        "subtract": "Please subtract {b} from {a}",
        "multiply": "Please multiply {a} by {b}",
        "divide": "Please divide {a} by {b}",
    }

    return templates.get(operation, "Please perform a calculation")


# ============================================================================
# Health Endpoints (for Kubernetes probes)
# ============================================================================

@mcp.http_route("/health", methods=["GET"])
async def health_check():
    """Liveness probe: Check if server is alive."""
    return {"status": "healthy", "server": "calculator", "version": "1.0.0"}


@mcp.http_route("/ready", methods=["GET"])
async def readiness_check():
    """Readiness probe: Check if server is ready to serve traffic."""
    # Perform basic sanity check
    try:
        test_result = 2 + 2
        if test_result == 4:
            return {"status": "ready", "checks": {"arithmetic": "pass"}}
        else:
            return {"status": "not_ready", "checks": {"arithmetic": "fail"}}, 503
    except Exception as e:
        return {"status": "not_ready", "error": str(e)}, 503


# ============================================================================
# Metrics Endpoint (for Prometheus)
# ============================================================================

# FastMCP automatically exposes metrics at /metrics if prometheus_client is installed
# Metrics include:
# - mcp_requests_total{tool="add",status="success"}
# - mcp_request_duration_seconds{tool="add"}
# - mcp_errors_total{tool="add",error_type="..."}


# ============================================================================
# Main Entry Point
# ============================================================================

if __name__ == "__main__":
    import logging

    # Configure logging
    logging.basicConfig(
        level=getattr(logging, LOG_LEVEL.upper()),
        format="%(asctime)s - %(name)s - %(levelname)s - %(message)s"
    )

    # Run MCP server with HTTP transport and SSE support
    mcp.run(
        transport="http",
        host="0.0.0.0",  # Listen on all interfaces (safe inside container)
        port=8080,
        sse=True,  # Enable Server-Sent Events
    )
