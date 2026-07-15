import { Video } from "lucide-react";

export default function VideoPage() {
  return (
    <div className="grid min-h-[calc(100vh-58px)] place-items-center bg-[#f1f4f8] p-6">
      <div className="w-full max-w-xl rounded-md bg-white p-10 text-center shadow-sm">
        <Video className="mx-auto h-12 w-12 text-[#367cf6]" />
        <h1 className="mt-5 text-2xl font-semibold text-[#344b72]">
          Video Monitoring
        </h1>
        <p className="mt-3 text-sm leading-7 text-[#71819c]">
          The screenshot-compatible video workspace is reserved here. Camera
          streams and playback will be connected after device capabilities and
          backend stream contracts are finalized.
        </p>
      </div>
    </div>
  );
}