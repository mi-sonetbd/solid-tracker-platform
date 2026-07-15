import { Car, MapPin, Navigation } from "lucide-react";

export function LoginVisual() {
  return (
    <section className="st-login-panel relative hidden min-h-[610px] overflow-hidden text-white md:block">
      <div className="absolute inset-0 opacity-35">
        <div className="absolute -right-10 top-5 h-32 w-32 rotate-45 rounded-[28px] bg-white/10" />
        <div className="absolute right-16 top-[-20px] h-32 w-32 rotate-45 rounded-[28px] bg-white/10" />
      </div>

      <div className="relative z-10 px-11 pt-12">
        <p className="text-[24px] font-light italic tracking-wide text-white/90">
          Making Connections
        </p>
        <h2 className="mt-3 text-[64px] font-black italic leading-none tracking-[-3px]">
          Simpler
        </h2>
      </div>

      <div className="absolute bottom-0 left-0 right-0 h-[390px] overflow-hidden">
        <div className="st-login-grid absolute -bottom-20 left-[-50px] h-[330px] w-[570px] opacity-75" />

        <div className="absolute bottom-[60px] left-[44px] h-[165px] w-[390px] skew-y-[-8deg] rounded-[28px] bg-gradient-to-br from-[#2586ee] to-[#143eca] shadow-[0_30px_50px_rgba(0,24,94,0.34)]">
          <div className="absolute inset-5 rounded-[22px] border border-white/10 bg-[#1b67da]/70">
            <div className="st-login-route absolute left-[38px] top-[58px] h-[52px] w-[245px] rotate-[-8deg] rounded-[50%]" />
            <div className="absolute left-[54px] top-[44px] h-3 w-3 rounded-full bg-cyan-200 shadow-[0_0_12px_rgba(150,235,255,0.9)]" />
            <div className="absolute bottom-[30px] right-[42px] h-3 w-3 rounded-full bg-cyan-200 shadow-[0_0_12px_rgba(150,235,255,0.9)]" />
          </div>
        </div>

        <div className="absolute bottom-[118px] left-[174px]">
          <div className="relative">
            <MapPin
              className="h-[190px] w-[190px] text-[#63d7f8] drop-shadow-[0_24px_28px_rgba(0,45,145,0.45)]"
              fill="url(#none)"
              strokeWidth={1.6}
            />
            <div className="absolute left-[67px] top-[58px] h-[54px] w-[54px] rounded-full border-[12px] border-[#199be6] bg-[#0b60d7]" />
          </div>
        </div>

        <div className="absolute bottom-[91px] left-[112px] grid h-12 w-16 place-items-center rounded-lg bg-white/95 text-[#2574e9] shadow-xl">
          <Car className="h-8 w-8" fill="#84c7ff" />
        </div>

        <div className="absolute bottom-[84px] right-[80px] grid h-12 w-16 place-items-center rounded-lg bg-white/95 text-[#2574e9] shadow-xl">
          <Car className="h-8 w-8" fill="#84c7ff" />
        </div>

        <Navigation
          className="absolute bottom-[108px] right-[157px] h-7 w-7 rotate-12 text-cyan-200"
          fill="currentColor"
        />
      </div>
    </section>
  );
}