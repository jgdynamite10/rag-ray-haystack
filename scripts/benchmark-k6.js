import http from "k6/http";
import { check, sleep } from "k6";

const target = __ENV.TARGET || "http://localhost:8000";

export const options = {
  vus: 5,
  duration: "30s",
};

export default function () {
  const res = http.post(
    `${target}/query`,
    JSON.stringify({ query: "What documents are available?" }),
    { headers: { "Content-Type": "application/json" } }
  );
  check(res, {
    "status is 200": (r) => r.status === 200,
  });
  sleep(1);
}
