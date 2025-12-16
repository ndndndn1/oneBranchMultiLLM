#!/usr/bin/env python3
"""
Multi-Claude Collaboration Bridge Server

실시간 통신이 필요한 경우 이 서버를 실행합니다.
파일 기반 통신의 대안으로 WebSocket을 통한 실시간 메시징을 제공합니다.

Usage:
    python scripts/collab_bridge.py [--port 8765]

Claude Code에서:
    ./scripts/collab.sh register "task"
    # 또는 bridge 서버 사용 시
    python scripts/collab_client.py connect
"""

import asyncio
import json
import os
import sys
import time
import hashlib
import argparse
from pathlib import Path
from datetime import datetime
from typing import Dict, Set, Optional
from dataclasses import dataclass, asdict
import signal

# WebSocket 서버 (설치 필요 시: pip install websockets)
try:
    import websockets
    from websockets.server import serve
    WEBSOCKETS_AVAILABLE = True
except ImportError:
    WEBSOCKETS_AVAILABLE = False
    print("Note: websockets not installed. Using file-based communication only.")
    print("Install with: pip install websockets")

# 설정
COLLAB_DIR = Path(".claude-collab")
DEFAULT_PORT = 8765


@dataclass
class ClaudeInstance:
    """Claude 인스턴스 정보"""
    id: str
    description: str
    registered_at: str
    last_heartbeat: float
    status: str
    current_task: Optional[str]
    websocket: Optional[any] = None

    def to_dict(self):
        d = asdict(self)
        d.pop('websocket', None)
        return d


@dataclass
class FileLock:
    """파일 잠금 정보"""
    path: str
    owner: str
    locked_at: str
    timestamp: float


@dataclass
class Message:
    """메시지"""
    from_id: str
    to_id: str
    msg_type: str
    content: str
    timestamp: str
    read: bool = False


class CollabBridge:
    """협업 브릿지 서버"""

    def __init__(self, port: int = DEFAULT_PORT):
        self.port = port
        self.instances: Dict[str, ClaudeInstance] = {}
        self.locks: Dict[str, FileLock] = {}
        self.message_queue: Dict[str, list] = {}
        self.connections: Dict[str, any] = {}
        self.running = False

    def generate_id(self) -> str:
        """고유 Claude ID 생성"""
        return f"claude-{hashlib.md5(str(time.time()).encode()).hexdigest()[:4]}"

    async def register_instance(self, websocket, data: dict) -> dict:
        """인스턴스 등록"""
        claude_id = data.get('id') or self.generate_id()
        description = data.get('description', 'No description')

        instance = ClaudeInstance(
            id=claude_id,
            description=description,
            registered_at=datetime.now().isoformat(),
            last_heartbeat=time.time(),
            status='active',
            current_task=None,
            websocket=websocket
        )

        self.instances[claude_id] = instance
        self.connections[claude_id] = websocket
        self.message_queue[claude_id] = []

        # 브로드캐스트
        await self.broadcast({
            'type': 'instance_joined',
            'instance': instance.to_dict()
        }, exclude=claude_id)

        return {
            'status': 'success',
            'id': claude_id,
            'message': f'Registered as {claude_id}'
        }

    async def unregister_instance(self, claude_id: str) -> dict:
        """인스턴스 등록 해제"""
        if claude_id in self.instances:
            # 잠금 해제
            locks_to_remove = [
                path for path, lock in self.locks.items()
                if lock.owner == claude_id
            ]
            for path in locks_to_remove:
                del self.locks[path]

            del self.instances[claude_id]
            self.connections.pop(claude_id, None)
            self.message_queue.pop(claude_id, None)

            await self.broadcast({
                'type': 'instance_left',
                'id': claude_id
            })

            return {'status': 'success', 'message': f'{claude_id} unregistered'}

        return {'status': 'error', 'message': 'Instance not found'}

    async def acquire_lock(self, claude_id: str, file_path: str) -> dict:
        """파일 잠금 획득"""
        if file_path in self.locks:
            existing = self.locks[file_path]
            if existing.owner == claude_id:
                return {'status': 'success', 'message': 'Already locked by you'}
            return {
                'status': 'error',
                'message': f'Locked by {existing.owner}',
                'owner': existing.owner,
                'since': existing.locked_at
            }

        lock = FileLock(
            path=file_path,
            owner=claude_id,
            locked_at=datetime.now().isoformat(),
            timestamp=time.time()
        )
        self.locks[file_path] = lock

        await self.broadcast({
            'type': 'lock_acquired',
            'path': file_path,
            'owner': claude_id
        })

        return {'status': 'success', 'message': f'Locked {file_path}'}

    async def release_lock(self, claude_id: str, file_path: str) -> dict:
        """파일 잠금 해제"""
        if file_path not in self.locks:
            return {'status': 'success', 'message': 'No lock exists'}

        lock = self.locks[file_path]
        if lock.owner != claude_id:
            return {'status': 'error', 'message': f'Owned by {lock.owner}'}

        del self.locks[file_path]

        await self.broadcast({
            'type': 'lock_released',
            'path': file_path,
            'owner': claude_id
        })

        return {'status': 'success', 'message': f'Unlocked {file_path}'}

    async def send_message(self, from_id: str, to_id: str, content: str, msg_type: str = 'normal') -> dict:
        """메시지 전송"""
        message = Message(
            from_id=from_id,
            to_id=to_id,
            msg_type=msg_type,
            content=content,
            timestamp=datetime.now().isoformat()
        )

        # 직접 전송 시도
        if to_id in self.connections:
            try:
                await self.connections[to_id].send(json.dumps({
                    'type': 'message',
                    'message': asdict(message)
                }))
                return {'status': 'success', 'message': 'Delivered'}
            except:
                pass

        # 큐에 저장
        if to_id not in self.message_queue:
            self.message_queue[to_id] = []
        self.message_queue[to_id].append(message)

        return {'status': 'success', 'message': 'Queued'}

    async def broadcast(self, data: dict, exclude: str = None):
        """모든 인스턴스에 브로드캐스트"""
        message = json.dumps(data)
        for claude_id, ws in list(self.connections.items()):
            if claude_id != exclude:
                try:
                    await ws.send(message)
                except:
                    pass

    async def get_status(self) -> dict:
        """전체 상태 반환"""
        return {
            'instances': {k: v.to_dict() for k, v in self.instances.items()},
            'locks': {k: asdict(v) for k, v in self.locks.items()},
            'active_count': len(self.instances)
        }

    async def handle_message(self, websocket, message: str, client_id: str = None) -> str:
        """메시지 처리"""
        try:
            data = json.loads(message)
            action = data.get('action')

            if action == 'register':
                result = await self.register_instance(websocket, data)
                return json.dumps(result)

            if not client_id:
                return json.dumps({'status': 'error', 'message': 'Not registered'})

            # Heartbeat 업데이트
            if client_id in self.instances:
                self.instances[client_id].last_heartbeat = time.time()

            handlers = {
                'unregister': lambda: self.unregister_instance(client_id),
                'lock': lambda: self.acquire_lock(client_id, data.get('path')),
                'unlock': lambda: self.release_lock(client_id, data.get('path')),
                'send': lambda: self.send_message(
                    client_id, data.get('to'), data.get('content'), data.get('msg_type', 'normal')
                ),
                'broadcast': lambda: self.broadcast_message(client_id, data.get('content')),
                'status': lambda: self.get_status(),
                'heartbeat': lambda: asyncio.coroutine(lambda: {'status': 'ok'})(),
                'get_messages': lambda: self.get_messages(client_id),
            }

            if action in handlers:
                result = await handlers[action]()
                return json.dumps(result)

            return json.dumps({'status': 'error', 'message': f'Unknown action: {action}'})

        except Exception as e:
            return json.dumps({'status': 'error', 'message': str(e)})

    async def broadcast_message(self, from_id: str, content: str) -> dict:
        """메시지 브로드캐스트"""
        for claude_id in self.instances:
            if claude_id != from_id:
                await self.send_message(from_id, claude_id, content)
        return {'status': 'success', 'message': 'Broadcast sent'}

    async def get_messages(self, claude_id: str) -> dict:
        """대기 중인 메시지 가져오기"""
        messages = self.message_queue.get(claude_id, [])
        self.message_queue[claude_id] = []
        return {
            'status': 'success',
            'messages': [asdict(m) for m in messages]
        }

    async def cleanup_stale(self):
        """비활성 인스턴스 정리"""
        current_time = time.time()
        timeout = 600  # 10분

        stale = [
            claude_id for claude_id, instance in self.instances.items()
            if current_time - instance.last_heartbeat > timeout
        ]

        for claude_id in stale:
            await self.unregister_instance(claude_id)
            print(f"Cleaned up stale instance: {claude_id}")

    async def handler(self, websocket):
        """WebSocket 연결 핸들러"""
        client_id = None

        try:
            async for message in websocket:
                response = await self.handle_message(websocket, message, client_id)
                await websocket.send(response)

                # 등록 성공 시 ID 저장
                try:
                    resp_data = json.loads(response)
                    if resp_data.get('status') == 'success' and 'id' in resp_data:
                        client_id = resp_data['id']
                except:
                    pass

        except websockets.exceptions.ConnectionClosed:
            pass
        finally:
            if client_id:
                await self.unregister_instance(client_id)

    async def periodic_cleanup(self):
        """주기적 정리 태스크"""
        while self.running:
            await asyncio.sleep(60)
            await self.cleanup_stale()

    async def run(self):
        """서버 실행"""
        if not WEBSOCKETS_AVAILABLE:
            print("WebSocket not available. Please use file-based communication.")
            return

        self.running = True

        # 정리 태스크 시작
        cleanup_task = asyncio.create_task(self.periodic_cleanup())

        print(f"Claude Collaboration Bridge Server")
        print(f"=" * 40)
        print(f"Port: {self.port}")
        print(f"WebSocket URL: ws://localhost:{self.port}")
        print(f"")
        print(f"Waiting for Claude instances to connect...")
        print(f"Press Ctrl+C to stop")

        try:
            async with serve(self.handler, "localhost", self.port):
                await asyncio.Future()  # 무한 대기
        except asyncio.CancelledError:
            pass
        finally:
            self.running = False
            cleanup_task.cancel()


# File-based fallback for non-WebSocket communication
class FileBasedCollab:
    """파일 기반 협업 (WebSocket 없이 사용)"""

    def __init__(self, claude_id: str = None):
        self.collab_dir = COLLAB_DIR
        self.claude_id = claude_id or f"claude-{hashlib.md5(str(time.time()).encode()).hexdigest()[:4]}"
        self._ensure_dirs()

    def _ensure_dirs(self):
        """디렉토리 생성"""
        dirs = [
            self.collab_dir / 'instances',
            self.collab_dir / 'locks',
            self.collab_dir / 'messages',
            self.collab_dir / 'tasks' / 'pending',
            self.collab_dir / 'tasks' / 'in_progress',
            self.collab_dir / 'tasks' / 'completed',
            self.collab_dir / 'conflicts',
            self.collab_dir / 'errors',
        ]
        for d in dirs:
            d.mkdir(parents=True, exist_ok=True)

    def register(self, description: str = ""):
        """인스턴스 등록"""
        instance_file = self.collab_dir / 'instances' / f'{self.claude_id}.json'
        data = {
            'id': self.claude_id,
            'description': description,
            'registered_at': datetime.now().isoformat(),
            'last_heartbeat': time.time(),
            'status': 'active',
            'current_task': None
        }
        instance_file.write_text(json.dumps(data, indent=2))
        (self.collab_dir / 'messages' / self.claude_id).mkdir(exist_ok=True)
        print(f"Registered as {self.claude_id}")

    def lock(self, file_path: str) -> bool:
        """파일 잠금"""
        encoded = file_path.replace('/', '_SLASH_').replace(' ', '_SPACE_')
        lock_file = self.collab_dir / 'locks' / f'{encoded}.lock'

        if lock_file.exists():
            data = json.loads(lock_file.read_text())
            if data['owner'] == self.claude_id:
                return True
            print(f"Locked by {data['owner']}")
            return False

        data = {
            'path': file_path,
            'owner': self.claude_id,
            'locked_at': datetime.now().isoformat(),
            'timestamp': time.time()
        }
        lock_file.write_text(json.dumps(data))
        return True

    def unlock(self, file_path: str) -> bool:
        """파일 잠금 해제"""
        encoded = file_path.replace('/', '_SLASH_').replace(' ', '_SPACE_')
        lock_file = self.collab_dir / 'locks' / f'{encoded}.lock'

        if not lock_file.exists():
            return True

        data = json.loads(lock_file.read_text())
        if data['owner'] != self.claude_id:
            print(f"Cannot unlock: owned by {data['owner']}")
            return False

        lock_file.unlink()
        return True

    def send(self, to_id: str, message: str, msg_type: str = 'normal'):
        """메시지 전송"""
        msg_dir = self.collab_dir / 'messages' / to_id
        msg_dir.mkdir(exist_ok=True)

        msg_file = msg_dir / f'{int(time.time())}_{self.claude_id}.msg'
        data = {
            'from': self.claude_id,
            'to': to_id,
            'type': msg_type,
            'message': message,
            'timestamp': datetime.now().isoformat(),
            'read': False
        }
        msg_file.write_text(json.dumps(data))

    def inbox(self) -> list:
        """받은 메시지 확인"""
        msg_dir = self.collab_dir / 'messages' / self.claude_id
        messages = []

        for msg_file in sorted(msg_dir.glob('*.msg')):
            data = json.loads(msg_file.read_text())
            messages.append(data)
            # 읽음 표시
            data['read'] = True
            msg_file.write_text(json.dumps(data))

        return messages

    def status(self) -> dict:
        """전체 상태"""
        instances = {}
        for f in (self.collab_dir / 'instances').glob('*.json'):
            data = json.loads(f.read_text())
            instances[data['id']] = data

        locks = {}
        for f in (self.collab_dir / 'locks').glob('*.lock'):
            data = json.loads(f.read_text())
            locks[data['path']] = data

        return {'instances': instances, 'locks': locks}


def main():
    parser = argparse.ArgumentParser(description='Multi-Claude Collaboration Bridge')
    parser.add_argument('--port', type=int, default=DEFAULT_PORT, help='Server port')
    parser.add_argument('--file-only', action='store_true', help='Use file-based only')
    args = parser.parse_args()

    if args.file_only or not WEBSOCKETS_AVAILABLE:
        print("Running in file-based mode")
        collab = FileBasedCollab()
        print(f"Collaboration directory: {COLLAB_DIR}")
        print("Use ./scripts/collab.sh for commands")
    else:
        bridge = CollabBridge(port=args.port)
        try:
            asyncio.run(bridge.run())
        except KeyboardInterrupt:
            print("\nShutting down...")


if __name__ == '__main__':
    main()
