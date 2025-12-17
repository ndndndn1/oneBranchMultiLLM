#!/usr/bin/env python3
"""
Multi-Claude Collaboration MCP Server
Claude Code가 자동으로 협업 기능을 사용할 수 있도록 MCP 프로토콜로 제공

이 서버를 통해 Claude Code는:
- 자동으로 세션 등록/해제
- 계획 공유 및 조회
- 실시간 수정 공유
- 제안/토론 참여
"""

import json
import os
import sys
import hashlib
import time
from datetime import datetime
from pathlib import Path
from typing import Any

# MCP SDK imports
try:
    from mcp.server import Server
    from mcp.server.stdio import stdio_server
    from mcp.types import Tool, TextContent
    HAS_MCP = True
except ImportError:
    HAS_MCP = False
    print("MCP SDK not installed. Run: pip install mcp", file=sys.stderr)

# Configuration
COLLAB_DIR = Path(".claude-collab")
INSTANCES_DIR = COLLAB_DIR / "instances"
PLANS_DIR = COLLAB_DIR / "plans"
EDITS_DIR = COLLAB_DIR / "edits"
PROPOSALS_DIR = COLLAB_DIR / "proposals"
DISCUSSIONS_DIR = COLLAB_DIR / "discussions"
MESSAGES_DIR = COLLAB_DIR / "messages"

def get_claude_id() -> str:
    """Generate or get Claude instance ID"""
    env_id = os.environ.get("CLAUDE_ID")
    if env_id:
        return env_id
    # Generate from hostname + pid for uniqueness
    hostname = os.uname().nodename
    pid = os.getpid()
    hash_input = f"{hostname}-{pid}-{time.time()}"
    return f"claude-{hashlib.md5(hash_input.encode()).hexdigest()[:8]}"

def ensure_dirs():
    """Ensure all collaboration directories exist"""
    for d in [INSTANCES_DIR, PLANS_DIR, EDITS_DIR, PROPOSALS_DIR, DISCUSSIONS_DIR, MESSAGES_DIR]:
        d.mkdir(parents=True, exist_ok=True)

def timestamp() -> int:
    return int(time.time())

def datetime_str() -> str:
    return datetime.now().strftime("%Y-%m-%d %H:%M:%S")

def encode_path(path: str) -> str:
    return path.replace("/", "_SLASH_").replace(" ", "_SPACE_")

class CollabServer:
    def __init__(self):
        self.claude_id = get_claude_id()
        ensure_dirs()

    # ========== Instance Management ==========

    def register(self, description: str = "No description") -> dict:
        """Register this Claude instance for collaboration"""
        instance_file = INSTANCES_DIR / f"{self.claude_id}.json"
        data = {
            "id": self.claude_id,
            "description": description,
            "registered_at": datetime_str(),
            "last_heartbeat": timestamp(),
            "status": "active",
            "current_task": None,
            "locked_files": []
        }
        instance_file.write_text(json.dumps(data, indent=2))

        # Create message directory
        (MESSAGES_DIR / self.claude_id).mkdir(exist_ok=True)

        return {"success": True, "claude_id": self.claude_id, "message": f"Registered as {self.claude_id}"}

    def unregister(self) -> dict:
        """Unregister and clean up"""
        instance_file = INSTANCES_DIR / f"{self.claude_id}.json"
        if instance_file.exists():
            instance_file.unlink()
        return {"success": True, "message": f"Unregistered {self.claude_id}"}

    def heartbeat(self) -> dict:
        """Send heartbeat to indicate active status"""
        instance_file = INSTANCES_DIR / f"{self.claude_id}.json"
        if instance_file.exists():
            data = json.loads(instance_file.read_text())
            data["last_heartbeat"] = timestamp()
            instance_file.write_text(json.dumps(data, indent=2))
            return {"success": True}
        return {"success": False, "error": "Not registered"}

    def get_overview(self) -> dict:
        """Get collaboration overview - what's happening now"""
        current_time = timestamp()

        # Count active instances
        active_instances = []
        for f in INSTANCES_DIR.glob("*.json"):
            data = json.loads(f.read_text())
            age = current_time - data.get("last_heartbeat", 0)
            if age < 600:  # 10 minutes
                active_instances.append({
                    "id": data["id"],
                    "description": data.get("description", ""),
                    "is_me": data["id"] == self.claude_id
                })

        # Get active plans
        active_plans = []
        for f in PLANS_DIR.glob("*.json"):
            data = json.loads(f.read_text())
            if data.get("status") in ["proposed", "in_progress"]:
                active_plans.append({
                    "id": data["id"],
                    "title": data["title"],
                    "author": data["author"],
                    "status": data["status"],
                    "target_files": data.get("target_files", "")
                })

        # Get active edits
        active_edits = []
        for f in EDITS_DIR.glob("*.json"):
            data = json.loads(f.read_text())
            age = current_time - data.get("timestamp", 0)
            if data.get("status") == "in_progress" and age < 1800:  # 30 minutes
                active_edits.append({
                    "file": data["file"],
                    "editor": data["editor"],
                    "change_type": data.get("change_type", "modify"),
                    "description": data.get("description", ""),
                    "is_me": data["editor"] == self.claude_id
                })

        # Get open proposals
        open_proposals = []
        for f in PROPOSALS_DIR.glob("*.json"):
            data = json.loads(f.read_text())
            if data.get("status") == "open":
                open_proposals.append({
                    "id": data["id"],
                    "type": data["type"],
                    "title": data["title"],
                    "author": data["author"],
                    "agrees": len(data.get("votes", {}).get("agree", [])),
                    "disagrees": len(data.get("votes", {}).get("disagree", []))
                })

        # Get active discussions
        active_discussions = []
        for f in DISCUSSIONS_DIR.glob("*.json"):
            data = json.loads(f.read_text())
            if data.get("status") == "active":
                active_discussions.append({
                    "id": data["id"],
                    "topic": data["topic"],
                    "initiator": data["initiator"],
                    "message_count": len(data.get("messages", []))
                })

        # Get unread messages
        unread = []
        msg_dir = MESSAGES_DIR / self.claude_id
        if msg_dir.exists():
            for f in msg_dir.glob("*.msg"):
                data = json.loads(f.read_text())
                if not data.get("read", False):
                    unread.append({
                        "from": data["from"],
                        "message": data["message"],
                        "type": data.get("type", "normal")
                    })

        return {
            "my_id": self.claude_id,
            "active_instances": active_instances,
            "active_plans": active_plans,
            "active_edits": active_edits,
            "open_proposals": open_proposals,
            "active_discussions": active_discussions,
            "unread_messages": unread
        }

    # ========== Plan Sharing ==========

    def share_plan(self, title: str, description: str = "", target_files: str = "") -> dict:
        """Share an implementation plan before starting work"""
        plan_id = f"{timestamp()}_{self.claude_id}"
        plan_file = PLANS_DIR / f"{plan_id}.json"

        data = {
            "id": plan_id,
            "author": self.claude_id,
            "title": title,
            "description": description,
            "target_files": target_files,
            "status": "proposed",
            "created_at": datetime_str(),
            "comments": [],
            "approvals": [],
            "implementation_started": False
        }
        plan_file.write_text(json.dumps(data, indent=2))
        self._broadcast(f"[PLAN] {self.claude_id} shared a plan: {title}")

        return {"success": True, "plan_id": plan_id, "message": f"Plan shared: {title}"}

    def view_plans(self) -> dict:
        """View all shared plans"""
        plans = []
        for f in PLANS_DIR.glob("*.json"):
            data = json.loads(f.read_text())
            plans.append(data)
        return {"plans": sorted(plans, key=lambda x: x.get("created_at", ""), reverse=True)}

    def comment_plan(self, plan_id: str, comment: str) -> dict:
        """Comment on a plan"""
        plan_file = PLANS_DIR / f"{plan_id}.json"
        if not plan_file.exists():
            return {"success": False, "error": f"Plan not found: {plan_id}"}

        data = json.loads(plan_file.read_text())
        data["comments"].append({
            "author": self.claude_id,
            "text": comment,
            "timestamp": datetime_str()
        })
        plan_file.write_text(json.dumps(data, indent=2))

        # Notify author
        self._send_message(data["author"], f"[COMMENT] {self.claude_id} commented: {comment}")
        return {"success": True}

    def approve_plan(self, plan_id: str) -> dict:
        """Approve a plan"""
        plan_file = PLANS_DIR / f"{plan_id}.json"
        if not plan_file.exists():
            return {"success": False, "error": f"Plan not found: {plan_id}"}

        data = json.loads(plan_file.read_text())
        if self.claude_id not in data["approvals"]:
            data["approvals"].append(self.claude_id)
        plan_file.write_text(json.dumps(data, indent=2))

        self._send_message(data["author"], f"[APPROVED] {self.claude_id} approved your plan: {data['title']}")
        return {"success": True}

    def start_plan(self, plan_id: str) -> dict:
        """Start implementing a plan"""
        plan_file = PLANS_DIR / f"{plan_id}.json"
        if not plan_file.exists():
            return {"success": False, "error": f"Plan not found: {plan_id}"}

        data = json.loads(plan_file.read_text())
        data["status"] = "in_progress"
        data["implementation_started"] = True
        data["started_at"] = datetime_str()
        plan_file.write_text(json.dumps(data, indent=2))

        self._broadcast(f"[IMPLEMENTATION] {self.claude_id} started: {data['title']}")
        return {"success": True}

    def complete_plan(self, plan_id: str) -> dict:
        """Mark plan as completed"""
        plan_file = PLANS_DIR / f"{plan_id}.json"
        if not plan_file.exists():
            return {"success": False, "error": f"Plan not found: {plan_id}"}

        data = json.loads(plan_file.read_text())
        data["status"] = "completed"
        data["completed_at"] = datetime_str()
        plan_file.write_text(json.dumps(data, indent=2))

        self._broadcast(f"[COMPLETED] {self.claude_id} completed: {data['title']}")
        return {"success": True}

    # ========== Live Editing ==========

    def share_edit(self, file_path: str, change_type: str = "modify", description: str = "") -> dict:
        """Share that you're editing a file"""
        encoded = encode_path(file_path)
        edit_file = EDITS_DIR / f"{encoded}_{self.claude_id}.json"

        data = {
            "file": file_path,
            "editor": self.claude_id,
            "change_type": change_type,
            "description": description,
            "started_at": datetime_str(),
            "timestamp": timestamp(),
            "status": "in_progress"
        }
        edit_file.write_text(json.dumps(data, indent=2))

        # Check for concurrent edits
        conflicts = []
        for f in EDITS_DIR.glob(f"{encoded}_*.json"):
            if f != edit_file:
                other_data = json.loads(f.read_text())
                if other_data.get("status") == "in_progress":
                    conflicts.append(other_data["editor"])
                    self._send_message(
                        other_data["editor"],
                        f"[CONCURRENT EDIT] {self.claude_id} is also editing {file_path}",
                        "urgent"
                    )

        result = {"success": True, "message": f"Edit shared: {file_path}"}
        if conflicts:
            result["warning"] = f"Concurrent editors: {', '.join(conflicts)}"
        return result

    def view_edits(self) -> dict:
        """View all active edits"""
        edits = []
        current_time = timestamp()
        for f in EDITS_DIR.glob("*.json"):
            data = json.loads(f.read_text())
            age = current_time - data.get("timestamp", 0)
            status = data.get("status", "in_progress")
            if age > 1800:
                status = "stale"
            edits.append({
                **data,
                "status": status,
                "age_seconds": age,
                "is_me": data["editor"] == self.claude_id
            })
        return {"edits": edits}

    def finish_edit(self, file_path: str) -> dict:
        """Mark edit as finished"""
        encoded = encode_path(file_path)
        edit_file = EDITS_DIR / f"{encoded}_{self.claude_id}.json"

        if edit_file.exists():
            data = json.loads(edit_file.read_text())
            data["status"] = "completed"
            data["finished_at"] = datetime_str()
            edit_file.write_text(json.dumps(data, indent=2))
            return {"success": True}
        return {"success": False, "error": "No active edit found"}

    # ========== Collaborative Thinking ==========

    def propose(self, proposal_type: str, title: str, details: str = "") -> dict:
        """Submit a proposal for discussion"""
        proposal_id = f"{timestamp()}_{self.claude_id}"
        proposal_file = PROPOSALS_DIR / f"{proposal_id}.json"

        data = {
            "id": proposal_id,
            "type": proposal_type,
            "author": self.claude_id,
            "title": title,
            "details": details,
            "created_at": datetime_str(),
            "votes": {"agree": [], "disagree": []},
            "responses": [],
            "status": "open"
        }
        proposal_file.write_text(json.dumps(data, indent=2))

        type_icons = {"approach": "💡", "alternative": "🔀", "optimization": "⚡", "question": "❓"}
        icon = type_icons.get(proposal_type, "💡")
        self._broadcast(f"[PROPOSAL] {icon} {self.claude_id}: {title}")

        return {"success": True, "proposal_id": proposal_id}

    def vote(self, proposal_id: str, vote: str) -> dict:
        """Vote on a proposal (agree/disagree)"""
        proposal_file = PROPOSALS_DIR / f"{proposal_id}.json"
        if not proposal_file.exists():
            return {"success": False, "error": "Proposal not found"}

        data = json.loads(proposal_file.read_text())
        vote_key = "agree" if vote == "agree" else "disagree"
        if self.claude_id not in data["votes"][vote_key]:
            data["votes"][vote_key].append(self.claude_id)
        proposal_file.write_text(json.dumps(data, indent=2))

        self._send_message(data["author"], f"[VOTE] {self.claude_id} voted {vote} on: {data['title']}")
        return {"success": True}

    def respond_to_proposal(self, proposal_id: str, response: str) -> dict:
        """Respond to a proposal"""
        proposal_file = PROPOSALS_DIR / f"{proposal_id}.json"
        if not proposal_file.exists():
            return {"success": False, "error": "Proposal not found"}

        data = json.loads(proposal_file.read_text())
        data["responses"].append({
            "author": self.claude_id,
            "text": response,
            "timestamp": datetime_str()
        })
        proposal_file.write_text(json.dumps(data, indent=2))

        self._send_message(data["author"], f"[RESPONSE] {self.claude_id}: {response}")
        return {"success": True}

    # ========== Discussions ==========

    def start_discussion(self, topic: str, initial_message: str = "") -> dict:
        """Start a discussion thread"""
        discussion_id = f"{timestamp()}_{self.claude_id}"
        discussion_file = DISCUSSIONS_DIR / f"{discussion_id}.json"

        data = {
            "id": discussion_id,
            "topic": topic,
            "initiator": self.claude_id,
            "created_at": datetime_str(),
            "messages": [{
                "author": self.claude_id,
                "text": initial_message or f"Let's discuss: {topic}",
                "timestamp": datetime_str()
            }],
            "participants": [self.claude_id],
            "status": "active"
        }
        discussion_file.write_text(json.dumps(data, indent=2))

        self._broadcast(f"[DISCUSSION] 💬 {self.claude_id} started: {topic}")
        return {"success": True, "discussion_id": discussion_id}

    def reply_to_discussion(self, discussion_id: str, message: str) -> dict:
        """Reply to a discussion"""
        discussion_file = DISCUSSIONS_DIR / f"{discussion_id}.json"
        if not discussion_file.exists():
            return {"success": False, "error": "Discussion not found"}

        data = json.loads(discussion_file.read_text())
        data["messages"].append({
            "author": self.claude_id,
            "text": message,
            "timestamp": datetime_str()
        })
        if self.claude_id not in data["participants"]:
            data["participants"].append(self.claude_id)
        discussion_file.write_text(json.dumps(data, indent=2))

        # Notify other participants
        for participant in data["participants"]:
            if participant != self.claude_id:
                self._send_message(participant, f"[REPLY] {self.claude_id} in '{data['topic']}': {message}")

        return {"success": True}

    def resolve_discussion(self, discussion_id: str, resolution: str = "Resolved") -> dict:
        """Resolve a discussion"""
        discussion_file = DISCUSSIONS_DIR / f"{discussion_id}.json"
        if not discussion_file.exists():
            return {"success": False, "error": "Discussion not found"}

        data = json.loads(discussion_file.read_text())
        data["status"] = "resolved"
        data["resolution"] = resolution
        data["resolved_at"] = datetime_str()
        data["resolved_by"] = self.claude_id
        discussion_file.write_text(json.dumps(data, indent=2))

        self._broadcast(f"[RESOLVED] '{data['topic']}' by {self.claude_id}: {resolution}")
        return {"success": True}

    # ========== Messaging ==========

    def _send_message(self, target: str, message: str, msg_type: str = "normal"):
        """Internal: Send message to another Claude"""
        target_dir = MESSAGES_DIR / target
        target_dir.mkdir(exist_ok=True)

        msg_file = target_dir / f"{timestamp()}_{self.claude_id}.msg"
        data = {
            "from": self.claude_id,
            "to": target,
            "type": msg_type,
            "message": message,
            "timestamp": datetime_str(),
            "read": False
        }
        msg_file.write_text(json.dumps(data, indent=2))

    def _broadcast(self, message: str, msg_type: str = "system"):
        """Internal: Broadcast to all instances"""
        for f in INSTANCES_DIR.glob("*.json"):
            data = json.loads(f.read_text())
            if data["id"] != self.claude_id:
                self._send_message(data["id"], message, msg_type)

    def send_message(self, target: str, message: str) -> dict:
        """Send a direct message to another Claude"""
        self._send_message(target, message, "normal")
        return {"success": True}

    def get_inbox(self) -> dict:
        """Get all messages for this Claude"""
        messages = []
        msg_dir = MESSAGES_DIR / self.claude_id
        if msg_dir.exists():
            for f in sorted(msg_dir.glob("*.msg")):
                data = json.loads(f.read_text())
                messages.append(data)
                # Mark as read
                data["read"] = True
                f.write_text(json.dumps(data, indent=2))
        return {"messages": messages}


# ========== MCP Server Setup ==========

if HAS_MCP:
    server = Server("collab-server")
    collab = CollabServer()

    @server.list_tools()
    async def list_tools() -> list[Tool]:
        return [
            Tool(
                name="collab_register",
                description="Register this Claude for collaboration. Call this at session start.",
                inputSchema={
                    "type": "object",
                    "properties": {
                        "description": {"type": "string", "description": "Brief description of your task"}
                    }
                }
            ),
            Tool(
                name="collab_overview",
                description="Get collaboration overview: active Claudes, plans, edits, proposals. Call this to understand current state.",
                inputSchema={"type": "object", "properties": {}}
            ),
            Tool(
                name="collab_share_plan",
                description="Share your implementation plan BEFORE starting work. Required for collaboration.",
                inputSchema={
                    "type": "object",
                    "properties": {
                        "title": {"type": "string", "description": "Plan title"},
                        "description": {"type": "string", "description": "Detailed description"},
                        "target_files": {"type": "string", "description": "Files you'll modify"}
                    },
                    "required": ["title"]
                }
            ),
            Tool(
                name="collab_view_plans",
                description="View all shared plans from other Claudes",
                inputSchema={"type": "object", "properties": {}}
            ),
            Tool(
                name="collab_start_plan",
                description="Mark that you're starting to implement a plan",
                inputSchema={
                    "type": "object",
                    "properties": {"plan_id": {"type": "string"}},
                    "required": ["plan_id"]
                }
            ),
            Tool(
                name="collab_complete_plan",
                description="Mark a plan as completed",
                inputSchema={
                    "type": "object",
                    "properties": {"plan_id": {"type": "string"}},
                    "required": ["plan_id"]
                }
            ),
            Tool(
                name="collab_share_edit",
                description="Share that you're editing a file. Warns if others are editing the same file.",
                inputSchema={
                    "type": "object",
                    "properties": {
                        "file_path": {"type": "string"},
                        "change_type": {"type": "string", "enum": ["add", "modify", "delete", "refactor"]},
                        "description": {"type": "string"}
                    },
                    "required": ["file_path", "description"]
                }
            ),
            Tool(
                name="collab_view_edits",
                description="View what files other Claudes are currently editing",
                inputSchema={"type": "object", "properties": {}}
            ),
            Tool(
                name="collab_finish_edit",
                description="Mark that you finished editing a file",
                inputSchema={
                    "type": "object",
                    "properties": {"file_path": {"type": "string"}},
                    "required": ["file_path"]
                }
            ),
            Tool(
                name="collab_propose",
                description="Propose an approach, ask a question, or suggest an alternative",
                inputSchema={
                    "type": "object",
                    "properties": {
                        "type": {"type": "string", "enum": ["approach", "alternative", "optimization", "question"]},
                        "title": {"type": "string"},
                        "details": {"type": "string"}
                    },
                    "required": ["type", "title"]
                }
            ),
            Tool(
                name="collab_vote",
                description="Vote agree or disagree on a proposal",
                inputSchema={
                    "type": "object",
                    "properties": {
                        "proposal_id": {"type": "string"},
                        "vote": {"type": "string", "enum": ["agree", "disagree"]}
                    },
                    "required": ["proposal_id", "vote"]
                }
            ),
            Tool(
                name="collab_discuss",
                description="Start a discussion thread about a topic",
                inputSchema={
                    "type": "object",
                    "properties": {
                        "topic": {"type": "string"},
                        "initial_message": {"type": "string"}
                    },
                    "required": ["topic"]
                }
            ),
            Tool(
                name="collab_reply",
                description="Reply to a discussion",
                inputSchema={
                    "type": "object",
                    "properties": {
                        "discussion_id": {"type": "string"},
                        "message": {"type": "string"}
                    },
                    "required": ["discussion_id", "message"]
                }
            ),
            Tool(
                name="collab_inbox",
                description="Check messages from other Claudes",
                inputSchema={"type": "object", "properties": {}}
            ),
            Tool(
                name="collab_send",
                description="Send a direct message to another Claude",
                inputSchema={
                    "type": "object",
                    "properties": {
                        "target": {"type": "string", "description": "Target Claude ID"},
                        "message": {"type": "string"}
                    },
                    "required": ["target", "message"]
                }
            ),
            Tool(
                name="collab_unregister",
                description="Unregister from collaboration. Call this at session end.",
                inputSchema={"type": "object", "properties": {}}
            ),
        ]

    @server.call_tool()
    async def call_tool(name: str, arguments: dict) -> list[TextContent]:
        try:
            if name == "collab_register":
                result = collab.register(arguments.get("description", ""))
            elif name == "collab_overview":
                result = collab.get_overview()
            elif name == "collab_share_plan":
                result = collab.share_plan(
                    arguments["title"],
                    arguments.get("description", ""),
                    arguments.get("target_files", "")
                )
            elif name == "collab_view_plans":
                result = collab.view_plans()
            elif name == "collab_start_plan":
                result = collab.start_plan(arguments["plan_id"])
            elif name == "collab_complete_plan":
                result = collab.complete_plan(arguments["plan_id"])
            elif name == "collab_share_edit":
                result = collab.share_edit(
                    arguments["file_path"],
                    arguments.get("change_type", "modify"),
                    arguments.get("description", "")
                )
            elif name == "collab_view_edits":
                result = collab.view_edits()
            elif name == "collab_finish_edit":
                result = collab.finish_edit(arguments["file_path"])
            elif name == "collab_propose":
                result = collab.propose(
                    arguments["type"],
                    arguments["title"],
                    arguments.get("details", "")
                )
            elif name == "collab_vote":
                result = collab.vote(arguments["proposal_id"], arguments["vote"])
            elif name == "collab_discuss":
                result = collab.start_discussion(
                    arguments["topic"],
                    arguments.get("initial_message", "")
                )
            elif name == "collab_reply":
                result = collab.reply_to_discussion(
                    arguments["discussion_id"],
                    arguments["message"]
                )
            elif name == "collab_inbox":
                result = collab.get_inbox()
            elif name == "collab_send":
                result = collab.send_message(arguments["target"], arguments["message"])
            elif name == "collab_unregister":
                result = collab.unregister()
            else:
                result = {"error": f"Unknown tool: {name}"}

            return [TextContent(type="text", text=json.dumps(result, indent=2, ensure_ascii=False))]
        except Exception as e:
            return [TextContent(type="text", text=json.dumps({"error": str(e)}))]

    async def main():
        async with stdio_server() as (read_stream, write_stream):
            await server.run(read_stream, write_stream)

    if __name__ == "__main__":
        import asyncio
        asyncio.run(main())
else:
    # Fallback: CLI mode for testing
    if __name__ == "__main__":
        collab = CollabServer()
        if len(sys.argv) < 2:
            print("Usage: collab-server.py <command> [args]")
            sys.exit(1)

        cmd = sys.argv[1]
        args = sys.argv[2:]

        if cmd == "register":
            print(json.dumps(collab.register(args[0] if args else "")))
        elif cmd == "overview":
            print(json.dumps(collab.get_overview(), indent=2, ensure_ascii=False))
        elif cmd == "share-plan":
            print(json.dumps(collab.share_plan(*args)))
        else:
            print(f"Unknown command: {cmd}")
