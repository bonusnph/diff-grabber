# คู่มือ Deploy Profit Monitor ด้วย Docker + Cloudflare Tunnel

โฟลเดอร์นี้ (`profit-monitor-for-docker`) เป็นเวอร์ชันที่ปรับมาให้ deploy แบบ **self-hosted บน server ทั่วไปผ่าน Docker**

## ข้อมูล Deployment ปัจจุบัน

| รายการ | ค่า |
| --- | --- |
| URL ที่ใช้งานจริง | https://profit.sumofx.co/ |
| Server IP | `68.183.185.48` (โดเมน `sumofx.co`) |
| Path บน server | `/home/profit-monitor` |
| Docker Hub image | `bonusnph/profit-monitor:latest` |
| บัญชี Cloudflare | `bonusnph@gmail.com` |
| Tunnel hostname | `profit.sumofx.co` → service `profit-monitor:3000` |

Flow โดยรวม:

```
เครื่อง Local (build image) → push ขึ้น Docker Hub → server (pull image + run)
                                                              │
                                                     Cloudflare Tunnel (cloudflared)
                                                              │
                                                     https://your-domain.com
```

---

## 1. โครงสร้างที่เกี่ยวข้อง

| ไฟล์ | หน้าที่ |
| --- | --- |
| `Dockerfile` | Build image ของแอป (SvelteKit + `adapter-node`) |
| `docker-compose.yml` | รัน container ของแอป + `cloudflared` บน server |
| `.env` | เก็บ `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `CLOUDFLARE_TUNNEL_TOKEN` (ห้าม commit ขึ้น git) |
| `package.json` (`docker:release`) | build + push image ขึ้น Docker Hub แบบ multi-arch (amd64 + arm64) |

> **สำคัญ:** image ต้อง build แบบ multi-platform (`linux/amd64` + `linux/arm64`) เพราะเครื่อง local ที่ build (เช่น Mac Apple Silicon) เป็น `arm64` แต่ server ส่วนใหญ่เป็น `amd64` ถ้า build ด้วย `docker build` ธรรมดาแล้ว push จะได้ image แค่ arch เดียว พอไป `docker compose pull` บน server ที่ arch ไม่ตรงจะเจอ error `no matching manifest for linux/amd64`

---

## 2. Build และ Push Image ขึ้น Docker Hub

จากเครื่อง local (ต้อง `docker login` ที่มีสิทธิ์ push ให้ repo `bonusnph/profit-monitor` ก่อน):

```bash
cd profit-monitor-for-docker
yarn docker:release
```

คำสั่งนี้จะรัน:

```bash
docker buildx build --platform linux/amd64,linux/arm64 -t bonusnph/profit-monitor:latest --push .
```

ตรวจสอบว่า push สำเร็จและมีทั้งสอง arch:

```bash
docker buildx imagetools inspect bonusnph/profit-monitor:latest
```

ควรเห็น `Platform: linux/amd64` และ `Platform: linux/arm64` ทั้งคู่ในผลลัพธ์

---

## 3. เตรียมไฟล์บน Server

Server **ไม่ต้องมี** `Dockerfile` หรือซอร์สโค้ดใดๆ เลย เพราะ image ถูก build ไว้แล้วบน Docker Hub ต้องมีแค่ 2 ไฟล์:

```
/home/profit-monitor/
├── docker-compose.yml
└── .env
```

Copy `docker-compose.yml` จากโฟลเดอร์นี้ไปวางที่ server แล้วสร้าง `.env` โดยใส่ค่า:

```bash
SUPABASE_URL=https://xxxxx.supabase.co
SUPABASE_ANON_KEY=xxxxxxxxxxxxxxxxxxxx
CLOUDFLARE_TUNNEL_TOKEN=xxxxxxxxxxxxxxxxxxxx   # ได้จากขั้นตอน Cloudflare ด้านล่าง
```

**Port ที่ใช้:** `docker-compose.yml` map พอร์ต host เป็น `3300:3000` เพื่อเลี่ยงไม่ให้ชนกับ container อื่นที่ใช้ 80 / 8080 / 3306 อยู่แล้วบน server เดียวกัน (แก้เลข `3300` ได้ถ้าจำเป็น)

---

## 4. Setup Cloudflare Tunnel (ทำครั้งเดียว)

### 4.1 สร้าง Tunnel ผ่าน Dashboard

1. เข้า [Cloudflare Zero Trust Dashboard](https://one.dash.cloudflare.com/) → login ด้วยบัญชี `bonusnph@gmail.com` → เลือก account ของ `sumofx.co`
2. ไปที่ **Networks → Tunnels → Create a tunnel**
3. เลือก connector type: **Cloudflared** → กด Next
4. ตั้งชื่อ tunnel เช่น `profit-monitor` → กด **Save tunnel**
5. หน้าถัดไปจะโชว์คำสั่งสำหรับรัน `cloudflared` พร้อม `--token <TOKEN>` ยาวๆ
   → **copy เฉพาะค่า token** (ส่วนที่ต่อจาก `--token`) เก็บไว้ ไม่ต้องรันคำสั่งนั้นตรงๆ เพราะเราจะรันผ่าน docker compose แทน

### 4.2 ตั้งค่า Public Hostname

ในหน้าเดียวกัน (หรือย้อนกลับไปที่ tunnel ที่สร้าง → แท็บ **Public Hostname**) กด **Add a public hostname**:

| Field | ค่าที่ใส่ |
| --- | --- |
| Subdomain | `profit` |
| Domain | `sumofx.co` |
| Path | เว้นว่าง |
| Type | `HTTP` |
| URL | `profit-monitor:3000` |

(ผลลัพธ์คือ `https://profit.sumofx.co` ตามที่ใช้งานจริงอยู่ในปัจจุบัน)

> ตรง URL ให้ใส่ `profit-monitor:3000` (ชื่อ service ใน `docker-compose.yml` + พอร์ตภายใน container) **ไม่ใช่** `localhost:3300` เพราะ `cloudflared` รันอยู่ใน docker network เดียวกับแอป เชื่อมกันผ่านชื่อ service ได้ตรงๆ

กด **Save** — ระบบจะสร้าง DNS record (CNAME) ให้อัตโนมัติ ไม่ต้องไปตั้งค่าใน DNS tab เอง

### 4.3 นำ Token ไปใส่ในเซิร์ฟเวอร์

เอา token จากขั้นตอน 4.1 ไปใส่ในไฟล์ `.env` บน server:

```bash
CLOUDFLARE_TUNNEL_TOKEN=<token ที่ copy มา>
```

---

## 5. Deploy บน Server

```bash
cd /home/profit-monitor
docker compose pull
docker compose up -d
```

ตรวจสอบสถานะ:

```bash
docker compose ps
docker compose logs -f cloudflared
```

ถ้าเห็น log แบบ `Registered tunnel connection` ใน `cloudflared` แสดงว่าเชื่อมสำเร็จ

ตรวจสอบแอปฝั่งใน container:

```bash
curl http://localhost:3300/api/health
```

ควรได้ผลลัพธ์ `{"status":"healthy", ...}`

สุดท้ายลองเปิดโดเมนจริง:

```
https://profit.sumofx.co/api/health
```

Cloudflare จะจัดการ HTTPS/SSL ให้อัตโนมัติ ไม่ต้องตั้ง certificate เอง และไม่ต้องเปิด port อะไรบน server/firewall เลย

---

## 6. อัพเดทเวอร์ชันใหม่ (Deploy ครั้งต่อไป)

**บนเครื่อง local:**

```bash
cd profit-monitor-for-docker
yarn docker:release
```

**บน server:**

```bash
cd /home/profit-monitor
docker compose pull
docker compose up -d
```

`docker compose up -d` จะดึง image ใหม่มาแทนตัวเดิมและ restart container ให้อัตโนมัติ

---

## 7. Troubleshooting

| ปัญหา | สาเหตุ / วิธีแก้ |
| --- | --- |
| `no matching manifest for linux/amd64` | Image build มาจาก arch เดียว (เช่น arm64 บน Mac) ให้ build ด้วย `yarn docker:release` (multi-arch) แล้ว push ใหม่ |
| `failed to read dockerfile: open Dockerfile: no such file` | รันจาก `docker compose up -d` แล้ว compose พยายาม build เอง (ไม่มี `build:` ใน compose แล้ว ถ้ายังเจอปัญหานี้ ตรวจว่า copy `docker-compose.yml` เวอร์ชันล่าสุดไปวางที่ server แล้ว) |
| container ตื่นไม่ทัน webhook จาก EA | เช็ค `docker compose logs profit-monitor` และ `curl localhost:3300/api/health` ว่า container รันอยู่จริง |
| `cloudflared` ขึ้น error เรื่อง token ผิด | ตรวจว่า copy `CLOUDFLARE_TUNNEL_TOKEN` มาครบไม่มีตัดตอน/มีช่องว่างแปลกๆ ใน `.env` |
| Public hostname ตั้งแล้วเข้าไม่ได้ | เช็คว่า URL ใน Public Hostname เป็น `profit-monitor:3000` (ชื่อ service ตรงกับ `docker-compose.yml`) ไม่ใช่ `localhost` |

---

## 8. คำสั่งที่ใช้บ่อย

```bash
# ดู log ของแอป
docker compose logs -f profit-monitor

# ดู log ของ tunnel
docker compose logs -f cloudflared

# restart ทั้งหมด
docker compose restart

# ปิดทั้งหมด
docker compose down

# เข้าไปดูภายใน container
docker exec -it profit-monitor-app sh
```
