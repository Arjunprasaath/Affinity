// backend/src/otel.ts
// OpenTelemetry -> Dash0. Imported first in server.ts.
// Does nothing until OTEL_EXPORTER_OTLP_ENDPOINT is set, so it is safe from minute one.
import { NodeSDK } from "@opentelemetry/sdk-node";
import { getNodeAutoInstrumentations } from "@opentelemetry/auto-instrumentations-node";
import { OTLPTraceExporter } from "@opentelemetry/exporter-trace-otlp-proto";
import { trace, SpanStatusCode } from "@opentelemetry/api";

if (process.env.OTEL_EXPORTER_OTLP_ENDPOINT) {
  process.env.OTEL_SERVICE_NAME ||= "orbit-backend";
  const sdk = new NodeSDK({
    // Reads OTEL_EXPORTER_OTLP_ENDPOINT and OTEL_EXPORTER_OTLP_HEADERS from env
    traceExporter: new OTLPTraceExporter(),
    instrumentations: [
      getNodeAutoInstrumentations({
        "@opentelemetry/instrumentation-fs": { enabled: false }, // too noisy
      }),
    ],
  });
  sdk.start();
  process.on("SIGTERM", () => void sdk.shutdown());
}

const tracer = trace.getTracer("orbit");

// Manual span helper. Use for: github.fetch, openai.extract, openai.reason,
// elastic.match, elastic.talks. Never put names or free text in span attributes.
export function withSpan<T>(
  name: string,
  fn: () => Promise<T>,
  attributes: Record<string, string | number | boolean> = {}
): Promise<T> {
  return tracer.startActiveSpan(name, async (span) => {
    span.setAttributes(attributes);
    try {
      return await fn();
    } catch (err) {
      span.setStatus({ code: SpanStatusCode.ERROR, message: (err as Error).message });
      throw err;
    } finally {
      span.end();
    }
  });
}
