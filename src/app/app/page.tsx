import type { Metadata } from "next";
import { Suspense } from "react";
import { connection } from "next/server";
import { Composer } from "@/components/compose/Composer";
import { getAiStatus } from "@/lib/ai";

export const metadata: Metadata = { title: "Compose" };

async function ComposerWithStatus() {
  await connection();
  return <Composer mode={getAiStatus().mode} />;
}

function ComposerFallback() {
  return (
    <div className="grid gap-8 lg:grid-cols-2" aria-busy="true">
      <div className="space-y-6">
        <div className="skeleton h-12 w-3/4 rounded-2xl" />
        <div className="skeleton h-44 rounded-3xl" />
        <div className="skeleton h-24 rounded-3xl" />
      </div>
      <div className="skeleton hidden h-72 rounded-3xl lg:block" />
    </div>
  );
}

export default function ComposePage() {
  return (
    <Suspense fallback={<ComposerFallback />}>
      <ComposerWithStatus />
    </Suspense>
  );
}
