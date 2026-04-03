const canvas = document.getElementById('canvas-mesh');
const ctx = canvas.getContext('2d');
const navbar = document.getElementById('navbar');

// Set canvas size
function resizeCanvas() {
    canvas.width = window.innerWidth;
    canvas.height = window.innerHeight;
}

window.addEventListener('resize', resizeCanvas);
resizeCanvas();

let mouse = { x: undefined, y: undefined };
window.addEventListener('mousemove', (e) => {
    mouse.x = e.x;
    mouse.y = e.y;
});

// Particle Class
class Particle {
    constructor() {
        this.reset();
    }

    reset() {
        this.x = Math.random() * canvas.width;
        this.y = Math.random() * canvas.height;
        this.vx = (Math.random() - 0.5) * 0.5;
        this.vy = (Math.random() - 0.5) * 0.5;
        this.size = Math.random() * 2 + 1;
        this.originalX = this.x;
        this.originalY = this.y;
    }

    update() {
        // Cursor Reaction
        if (mouse.x && mouse.y) {
            let dx = mouse.x - this.x;
            let dy = mouse.y - this.y;
            let dist = Math.sqrt(dx*dx + dy*dy);
            if (dist < 100) {
                this.x -= dx / 10;
                this.y -= dy / 10;
            }
        }

        this.x += this.vx;
        this.y += this.vy;

        if (this.x < 0 || this.x > canvas.width) this.vx *= -1;
        if (this.y < 0 || this.y > canvas.height) this.vy *= -1;
    }

    draw() {
        ctx.beginPath();
        ctx.arc(this.x, this.y, this.size, 0, Math.PI * 2);
        ctx.fillStyle = 'rgba(0, 242, 255, 0.5)';
        ctx.fill();
    }
}

const particles = Array.from({ length: 80 }, () => new Particle());

function animate() {
    ctx.clearRect(0, 0, canvas.width, canvas.height);
    
    particles.forEach((p, i) => {
        p.update();
        p.draw();

        // Draw connections
        for (let j = i + 1; j < particles.length; j++) {
            const p2 = particles[j];
            const dx = p.x - p2.x;
            const dy = p.y - p2.y;
            const dist = Math.sqrt(dx * dx + dy * dy);

            if (dist < 150) {
                ctx.beginPath();
                ctx.moveTo(p.x, p.y);
                ctx.lineTo(p2.x, p2.y);
                ctx.strokeStyle = `rgba(0, 242, 255, ${0.15 * (1 - dist / 150)})`;
                ctx.stroke();
            }
        }
    });

    requestAnimationFrame(animate);
}

animate();

// Navbar Scroll Effect
window.addEventListener('scroll', () => {
    if (window.scrollY > 50) {
        navbar.classList.add('scrolled');
    } else {
        navbar.classList.remove('scrolled');
    }
});

// Intersection Observer for Reveal Animations
const observerOptions = {
    threshold: 0.1,
    rootMargin: '0px 0px -50px 0px'
};

const observer = new IntersectionObserver((entries) => {
    entries.forEach(entry => {
        if (entry.isIntersecting) {
            entry.target.classList.add('visible');
        }
    });
}, observerOptions);

document.querySelectorAll('[data-reveal]').forEach(el => observer.observe(el));

// Mobile Menu Toggle
const menuToggle = document.getElementById('menu-toggle');
const navLinks = document.getElementById('nav-links');

if (menuToggle && navLinks) {
    menuToggle.addEventListener('click', () => {
        navLinks.classList.toggle('active');
        const icon = menuToggle.querySelector('i');
        icon.classList.toggle('fa-bars');
        icon.classList.toggle('fa-times');
    });
}

// Smooth Scroll for local links
document.querySelectorAll('a[href^="#"]').forEach(anchor => {
    anchor.addEventListener('click', function (e) {
        e.preventDefault();
        
        // Close mobile menu if open
        if (navLinks.classList.contains('active')) {
            navLinks.classList.remove('active');
            const icon = menuToggle.querySelector('i');
            icon.classList.add('fa-bars');
            icon.classList.remove('fa-times');
        }

        const target = document.querySelector(this.getAttribute('href'));
        if (target) {
            const offset = 80; // Account for fixed header
            const bodyRect = document.body.getBoundingClientRect().top;
            const elementRect = target.getBoundingClientRect().top;
            const elementPosition = elementRect - bodyRect;
            const offsetPosition = elementPosition - offset;

            window.scrollTo({
                top: offsetPosition,
                behavior: 'smooth'
            });
        }
    });
});

// 3D Tilt Effect Logic
const tiltElements = document.querySelectorAll('.hero-image, .feature-card, .tech-card');
tiltElements.forEach(el => {
    el.addEventListener('mousemove', (e) => {
        const rect = el.getBoundingClientRect();
        const x = e.clientX - rect.left;
        const y = e.clientY - rect.top;
        const centerX = rect.width / 2;
        const centerY = rect.height / 2;
        const rotateX = (centerY - y) / 10;
        const rotateY = (x - centerX) / 10;
        el.style.transform = `perspective(1000px) rotateX(${rotateX}deg) rotateY(${rotateY}deg)`;
    });
    
    el.addEventListener('mouseleave', () => {
        el.style.transform = `perspective(1000px) rotateX(0deg) rotateY(0deg)`;
    });
});

// --- ULTIMATE EDITION FEATURES ---

// Mesh Lab Simulator
const labCanvas = document.createElement('canvas');
const labSection = document.getElementById('mesh-lab-container');
if (labSection) {
    labSection.appendChild(labCanvas);
    const lctx = labCanvas.getContext('2d');
    let labNodes = [];

    function resizeLab() {
        labCanvas.width = labSection.offsetWidth;
        labCanvas.height = labSection.offsetHeight;
    }
    resizeLab();
    window.addEventListener('resize', resizeLab);

    let meshMode = 'random'; // 'random' or 'shape'
    
    class Node {
        constructor(x, y) {
            this.x = x || Math.random() * labCanvas.width;
            this.y = y || Math.random() * labCanvas.height;
            this.vx = (Math.random() - 0.5) * 0.4;
            this.vy = (Math.random() - 0.5) * 0.4;
            this.targetX = this.x;
            this.targetY = this.y;
            this.pulse = Math.random() * Math.PI * 2;
            this.flash = 0;
            this.delay = 0;
        }
        update() {
            if (meshMode === 'random') {
                this.x += this.vx;
                this.y += this.vy;
                if (this.x < 0 || this.x > labCanvas.width) this.vx *= -1;
                if (this.y < 0 || this.y > labCanvas.height) this.vy *= -1;
            } else {
                if (this.delay > 0) {
                    this.delay--;
                    // Still move randomly while waiting
                    this.x += this.vx;
                    this.y += this.vy;
                    if (this.x < 0 || this.x > labCanvas.width) this.vx *= -1;
                    if (this.y < 0 || this.y > labCanvas.height) this.vy *= -1;
                } else {
                    const dx = this.targetX - this.x;
                    const dy = this.targetY - this.y;
                    const d = Math.sqrt(dx*dx + dy*dy);
                    
                    if (d < 0.5) {
                        this.x = this.targetX;
                        this.y = this.targetY;
                    } else {
                        // Custom words form faster for a "snappy" live typing feel
                        const speed = meshMode === 'text' ? 0.02 : 0.006;
                        // Jitter reduces as we get closer for a "clear" landing
                        const jitter = Math.min(d * 0.1, 0.1);
                        this.x += dx * speed + (Math.random() - 0.5) * jitter;
                        this.y += dy * speed + (Math.random() - 0.5) * jitter;
                    }
                }
            }
            if (this.flash > 0) this.flash -= 0.05;
        }
        draw() {
            this.pulse += 0.05;
            const isShape = meshMode !== 'random';
            let r = (isShape ? 3 : 6) + Math.sin(this.pulse) * (isShape ? 1 : 2);
            if (this.flash > 0) r += this.flash * 8;
            
            lctx.beginPath();
            lctx.arc(this.x, this.y, r, 0, Math.PI * 2);
            lctx.fillStyle = this.flash > 0 ? `rgba(0, 242, 255, ${0.5 + this.flash})` : '#00F2FF';
            lctx.fill();
            lctx.strokeStyle = `rgba(0, 242, 255, ${isShape ? 0.1 : 0.2})`;
            lctx.lineWidth = isShape ? 3 : 8;
            lctx.stroke();
        }
    }

    // --- SHAPE GENERATION ---
    window.setMeshShape = function(shape) {
        meshMode = shape;
        
        // --- MODE-SPECIFIC NODE COUNTS ---
        const targetCount = shape === 'random' ? 30 : 50;
        if (labNodes.length < targetCount) {
            const toAdd = targetCount - labNodes.length;
            for (let i = 0; i < toAdd; i++) labNodes.push(new Node());
        } else if (labNodes.length > targetCount) {
            labNodes.length = targetCount;
        }

        if (shape === 'random') return;
        
        const centerX = labCanvas.width / 2;
        const centerY = labCanvas.height / 2;
        const size = 180;
        
        labNodes.forEach((node, i) => {
            const t = (i / labNodes.length) * Math.PI * 2;
            let tx, ty;
            
            if (shape === 'heart') {
                tx = 16 * Math.pow(Math.sin(t), 3);
                ty = -(13 * Math.cos(t) - 5 * Math.cos(2 * t) - 2 * Math.cos(3 * t) - Math.cos(4 * t));
                node.targetX = centerX + tx * 10;
                node.targetY = centerY + ty * 10;
            } else if (shape === 'logo') {
                // Stylized "Mesh Star" - Central hub with 6 radiating spokes
                const subIndex = i % 7; // 0=center, 1-6=spokes
                if (subIndex === 0) {
                    node.targetX = centerX + (Math.random() - 0.5) * 40;
                    node.targetY = centerY + (Math.random() - 0.5) * 40;
                } else {
                    const angle = ((subIndex - 1) / 6) * Math.PI * 2;
                    const hubDist = 120;
                    node.targetX = centerX + Math.cos(angle) * hubDist + (Math.random() - 0.5) * 30;
                    node.targetY = centerY + Math.sin(angle) * hubDist + (Math.random() - 0.5) * 30;
                }
            } else if (shape === 'triangle') {
                const side = i % 3;
                const p = (i / labNodes.length) * 3;
                if (p < 1) { // Base
                    node.targetX = centerX - size + (p * 2 * size);
                    node.targetY = centerY + size;
                } else if (p < 2) { // Right side
                    const p2 = p - 1;
                    node.targetX = centerX + size - (p2 * size);
                    node.targetY = centerY + size - (p2 * 2 * size);
                } else { // Left side
                    const p3 = p - 2;
                    node.targetX = centerX - (p3 * size);
                    node.targetY = centerY - size + (p3 * 2 * size);
                }
            } else if (shape === 'circle') {
                node.targetX = centerX + Math.cos(t) * size;
                node.targetY = centerY + Math.sin(t) * size;
            } else if (shape === 'grid') {
                const cols = 6;
                node.targetX = (centerX - 200) + (i % cols) * 80;
                node.targetY = (centerY - 150) + Math.floor(i / cols) * 80;
            } else if (shape === 'infinity') {
                const a = size + 50;
                const denom = 1 + Math.sin(t) * Math.sin(t);
                node.targetX = centerX + (a * Math.cos(t)) / denom;
                node.targetY = centerY + (a * Math.sin(t) * Math.cos(t)) / denom;
            } else if (shape === 'spiral') {
                const turns = 3;
                const p = i / labNodes.length;
                const currentRadius = p * size * 1.5;
                const currentAngle = p * Math.PI * 2 * turns;
                node.targetX = centerX + Math.cos(currentAngle) * currentRadius;
                node.targetY = centerY + Math.sin(currentAngle) * currentRadius;
            } else if (shape === 'star') {
                const p = i / labNodes.length;
                const numPoints = 5;
                const pointP = p * numPoints;
                const pointIndex = Math.floor(pointP);
                const localP = pointP - pointIndex;
                
                const outerRadius = size * 1.2;
                const innerRadius = size * 0.5;
                
                const angle1 = (pointIndex / numPoints) * Math.PI * 2 - Math.PI / 2;
                const angleHalf = ((pointIndex + 0.5) / numPoints) * Math.PI * 2 - Math.PI / 2;
                const angle2 = ((pointIndex + 1) / numPoints) * Math.PI * 2 - Math.PI / 2;
                
                if (localP < 0.5) {
                    const subP = localP * 2;
                    const x1 = Math.cos(angle1) * outerRadius;
                    const y1 = Math.sin(angle1) * outerRadius;
                    const x2 = Math.cos(angleHalf) * innerRadius;
                    const y2 = Math.sin(angleHalf) * innerRadius;
                    node.targetX = centerX + x1 + (x2 - x1) * subP;
                    node.targetY = centerY + y1 + (y2 - y1) * subP;
                } else {
                    const subP = (localP - 0.5) * 2;
                    const x1 = Math.cos(angleHalf) * innerRadius;
                    const y1 = Math.sin(angleHalf) * innerRadius;
                    const x2 = Math.cos(angle2) * outerRadius;
                    const y2 = Math.sin(angle2) * outerRadius;
                    node.targetX = centerX + x1 + (x2 - x1) * subP;
                    node.targetY = centerY + y1 + (y2 - y1) * subP;
                }
            }
        });
    };

    const textCanvas = document.createElement('canvas');
    const tctx = textCanvas.getContext('2d');

    window.setMeshText = function() {
        const input = document.getElementById('mesh-text-input');
        const text = input.value.trim() || 'AIRLINK';
        meshMode = 'text'; // Use distinct mode for faster formation

        // Use a font stack that prioritizes clean emojis
        tctx.font = 'bold 80px "Segoe UI Emoji", "Apple Color Emoji", "Noto Color Emoji", "Outfit", sans-serif';
        const textWidth = tctx.measureText(text.toUpperCase()).width;
        
        // Resize sampling canvas dynamically (Allow extra width for wider emojis)
        textCanvas.width = Math.max(textWidth + 150, 600);
        textCanvas.height = 180;
        
        tctx.clearRect(0, 0, textCanvas.width, textCanvas.height);
        tctx.fillStyle = 'white';
        tctx.font = 'bold 80px "Segoe UI Emoji", "Apple Color Emoji", "Noto Color Emoji", "Outfit", sans-serif'; 
        tctx.textAlign = 'center';
        tctx.textBaseline = 'middle';
        const cx = textCanvas.width / 2;
        const cy = textCanvas.height / 2;
        tctx.fillText(text, cx, cy); // Don't toUpperCase emojis

        const imageData = tctx.getImageData(0, 0, textCanvas.width, textCanvas.height).data;
        const points = [];
        const gap = 5; 

        // Sample COLUMN-WISE for better formation sequence
        for (let x = 0; x < textCanvas.width; x += gap) {
            for (let y = 0; y < textCanvas.height; y += gap) {
                const index = (y * textCanvas.width + x) * 4;
                // Check ALPHA channel (+3) to detect emoji pixels correctly
                if (imageData[index + 3] > 128) {
                    points.push({ x: x, y: y });
                }
            }
        }

        if (labNodes.length < points.length) {
            const toAdd = points.length - labNodes.length;
            for (let i = 0; i < toAdd; i++) labNodes.push(new Node());
        } else if (labNodes.length > points.length) {
            labNodes.length = points.length;
        }

        const availableWidth = labCanvas.width * 0.85;
        const availableHeight = labCanvas.height * 0.7;
        
        let scaleX = availableWidth / textWidth;
        let scaleY = availableHeight / 100;
        let finalScale = Math.min(scaleX, scaleY, 2.5);
        
        const centerX = labCanvas.width / 2;
        const centerY = labCanvas.height / 2;

        labNodes.forEach((node, i) => {
            const pt = points[i];
            const oldTargetX = node.targetX;
            node.targetX = centerX + (pt.x - cx) * finalScale;
            node.targetY = centerY + (pt.y - cy) * finalScale * 1.5;
            
            // Only reset delay if it's a new point or target moved significantly
            // This makes live typing feel "continuous"
            if (Math.abs(oldTargetX - node.targetX) > 20) {
                const normX = (node.targetX - (centerX - availableWidth/2)) / availableWidth;
                node.delay = normX * 800; 
            }
        });
    };

    class TravelingPacket {
        constructor(path) {
            this.path = path; // Array of [curr, prev]
            this.segmentIndex = path.length - 1;
            this.progress = 0;
            this.speed = 0.03;
        }
        update() {
            this.progress += this.speed;
            if (this.progress >= 1) {
                this.progress = 0;
                const [target, source] = this.path[this.segmentIndex];
                target.flash = 1; // Trigger Relay Glow
                this.segmentIndex--;
            }
        }
        draw() {
            if (this.segmentIndex < 0) return false;
            const [end, start] = this.path[this.segmentIndex];
            const x = start.x + (end.x - start.x) * this.progress;
            const y = start.y + (end.y - start.y) * this.progress;
            
            lctx.beginPath();
            lctx.arc(x, y, 5, 0, Math.PI * 2);
            lctx.fillStyle = '#FFFFFF';
            lctx.shadowBlur = 15;
            lctx.shadowColor = '#00F2FF';
            lctx.fill();
            lctx.shadowBlur = 0;
            return true;
        }
    }

    let packets = [];
    setInterval(() => {
        // Scroll-Sync Check: Only emit packets when visible or scroll is high enough
        const scrollFactor = window.scrollY / 2000;
        if (Math.random() < 0.5 + scrollFactor) {
            const path = findShortestPath(labNodes);
            if (path && path.length > 0) packets.push(new TravelingPacket(path));
        }
        if (packets.length > 10) packets.shift();
    }, 1000);

    // Initial nodes
    for(let i=0; i<20; i++) labNodes.push(new Node());

    // Auto-generate nodes up to a limit
    setInterval(() => {
        if (labNodes.length < 35) {
            labNodes.push(new Node());
        }
    }, 2000);

    labCanvas.addEventListener('mousedown', (e) => {
        const rect = labCanvas.getBoundingClientRect();
        labNodes.push(new Node(e.clientX - rect.left, e.clientY - rect.top));
        if (labNodes.length > 50) labNodes.shift();
    });

    function findShortestPath(nodes) {
        if (nodes.length < 2) return null;
        const start = nodes[0];
        const end = nodes[nodes.length - 1];
        
        const distances = new Map();
        const prev = new Map();
        const queue = [...nodes];
        
        nodes.forEach(n => distances.set(n, Infinity));
        distances.set(start, 0);
        
        while (queue.length > 0) {
            queue.sort((a, b) => distances.get(a) - distances.get(b));
            const u = queue.shift();
            if (u === end) break;
            if (distances.get(u) === Infinity) break;
            
            nodes.forEach(v => {
                const dist = Math.sqrt((u.x - v.x)**2 + (u.y - v.y)**2);
                if (dist < 180) {
                    const alt = distances.get(u) + dist;
                    if (alt < distances.get(v)) {
                        distances.set(v, alt);
                        prev.set(v, u);
                    }
                }
            });
        }
        
        let path = [];
        let curr = end;
        while (prev.has(curr)) {
            path.push([curr, prev.get(curr)]);
            curr = prev.get(curr);
        }
        return path;
    }

    function updateStats(path) {
        document.getElementById('stat-nodes').innerText = labNodes.length;
        document.getElementById('stat-hops').innerText = path ? path.length : '0';
        if (path && path.length > 0) {
            const directDist = Math.sqrt((labNodes[0].x - labNodes[labNodes.length-1].x)**2 + (labNodes[0].y - labNodes[labNodes.length-1].y)**2);
            let pathDist = 0;
            path.forEach(([u, v]) => {
                pathDist += Math.sqrt((u.x - v.x)**2 + (u.y - v.y)**2);
            });
            const efficiency = Math.round((directDist / pathDist) * 100);
            document.getElementById('stat-eff').innerText = efficiency + '%';
        } else {
            document.getElementById('stat-eff').innerText = '0%';
        }
    }

    function animateLab() {
        lctx.clearRect(0, 0, labCanvas.width, labCanvas.height);
        
        const isShape = meshMode !== 'random';
        labNodes.forEach(n => n.update());

        lctx.strokeStyle = `rgba(0, 242, 255, ${isShape ? 0.04 : 0.1})`;
        lctx.lineWidth = 1;
        const connectionDist = isShape ? 80 : 180;

        for (let i = 0; i < labNodes.length; i++) {
            for (let j = i + 1; j < labNodes.length; j++) {
                const dist = Math.sqrt((labNodes[i].x - labNodes[j].x)**2 + (labNodes[i].y - labNodes[j].y)**2);
                if (dist < connectionDist) {
                    lctx.beginPath();
                    lctx.moveTo(labNodes[i].x, labNodes[i].y);
                    lctx.lineTo(labNodes[j].x, labNodes[j].y);
                    lctx.stroke();
                }
            }
        }

        const path = findShortestPath(labNodes);
        updateStats(path);

        if (labNodes.length >= 2) {
            lctx.save();
            lctx.setLineDash([5, 10]);
            lctx.strokeStyle = 'rgba(112, 0, 255, 0.2)';
            lctx.beginPath();
            lctx.moveTo(labNodes[0].x, labNodes[0].y);
            lctx.lineTo(labNodes[labNodes.length-1].x, labNodes[labNodes.length-1].y);
            lctx.stroke();
            lctx.restore();
        }

        if (path && path.length > 0) {
            lctx.strokeStyle = '#7000FF';
            lctx.lineWidth = 3;
            lctx.shadowBlur = 15;
            lctx.shadowColor = '#7000FF';
            path.forEach(([u, v]) => {
                lctx.beginPath();
                lctx.moveTo(u.x, u.y);
                lctx.lineTo(v.x, v.y);
                lctx.stroke();
            });
            lctx.shadowBlur = 0;
        }

        packets = packets.filter(p => {
            p.update();
            return p.draw();
        });

        labNodes.forEach((node, idx) => {
            node.draw();
            if(idx === 0 || idx === labNodes.length-1) {
                lctx.beginPath();
                lctx.arc(node.x, node.y, 12, 0, Math.PI * 2);
                lctx.strokeStyle = idx === 0 ? '#00F2FF' : '#7000FF';
                lctx.lineWidth = 2;
                lctx.stroke();
            }
        });

        requestAnimationFrame(animateLab);
    }
    animateLab();
}


// --- EMAILJS INTEGRATION ---
(function() {
    // Replace with your actual Public Key from EmailJS Account > Settings
    emailjs.init({
      publicKey: "EcX4qrCdou0WD2P5u",
    });
})();

const contactForm = document.getElementById('contact-form');
const submitBtn = document.getElementById('submit-btn');
const formStatus = document.getElementById('form-status');

if (contactForm) {
    contactForm.addEventListener('submit', function(event) {
        event.preventDefault();
        
        // UI Feedback: Loading state
        submitBtn.classList.add('loading');
        submitBtn.disabled = true;
        const originalBtnText = submitBtn.innerHTML;
        submitBtn.innerHTML = '<span>Sending...</span> <i class="fa-solid fa-spinner fa-spin" style="margin-left: 10px;"></i>';
        
        formStatus.className = 'form-status';
        formStatus.innerText = '';

        // These IDs come from your EmailJS Dashboard
        const serviceID = 'service_vjtg4ps';
        const templateID = 'template_ht10bts';

        emailjs.sendForm(serviceID, templateID, this)
            .then(() => {
                submitBtn.classList.remove('loading');
                submitBtn.disabled = false;
                submitBtn.innerHTML = originalBtnText;
                
                formStatus.classList.add('success');
                formStatus.innerText = 'Message sent successfully! We will get back to you soon.';
                contactForm.reset();
                
                // Hide status after 5 seconds
                setTimeout(() => {
                    formStatus.style.display = 'none';
                }, 5000);
            }, (err) => {
                submitBtn.classList.remove('loading');
                submitBtn.disabled = false;
                submitBtn.innerHTML = originalBtnText;
                
                formStatus.classList.add('error');
                formStatus.innerText = 'Oops! Something went wrong. Please try again later.';
                console.error('EmailJS Error:', err);
            });
    });
}

// --- NETWORK COMPARISON SLIDER ---
const compareContainer = document.querySelector('.comparison-slider-container');
const sliderHandle = document.querySelector('.slider-handle');
const meshView = document.getElementById('mesh-view');

if (compareContainer) {
    let isDragging = false;
    
    const handleSlider = (e) => {
        const rect = compareContainer.getBoundingClientRect();
        const x = (e.clientX || e.touches[0].clientX) - rect.left;
        const percent = Math.min(Math.max((x / rect.width) * 100, 0), 100);
        
        meshView.style.width = percent + '%';
        sliderHandle.style.left = percent + '%';
    };

    sliderHandle.addEventListener('mousedown', () => isDragging = true);
    window.addEventListener('mouseup', () => isDragging = false);
    window.addEventListener('mousemove', (e) => { if (isDragging) handleSlider(e); });
    
    // Canvas Logic for Comparison
    const cCanvas = document.getElementById('canvas-centralized');
    const mCanvas = document.getElementById('canvas-mesh-simple');
    
    function initCompCanvas(canvas, mode) {
        const ctx = canvas.getContext('2d');
        canvas.width = compareContainer.offsetWidth;
        canvas.height = 500;
        
        let nodes = Array.from({ length: 15 }, () => ({
            x: Math.random() * canvas.width,
            y: Math.random() * canvas.height,
            vx: (Math.random() - 0.5) * 1,
            vy: (Math.random() - 0.5) * 1
        }));
        
        const server = { x: canvas.width/2, y: canvas.height/2 };

        function draw() {
            ctx.clearRect(0, 0, canvas.width, canvas.height);
            
            nodes.forEach(n => {
                n.x += n.vx;
                n.y += n.vy;
                if (n.x < 0 || n.x > canvas.width) n.vx *= -1;
                if (n.y < 0 || n.y > canvas.height) n.vy *= -1;
                
                ctx.beginPath();
                ctx.arc(n.x, n.y, 4, 0, Math.PI * 2);
                ctx.fillStyle = '#00F2FF';
                ctx.fill();
                
                if (mode === 'centralized') {
                    ctx.beginPath();
                    ctx.moveTo(n.x, n.y);
                    ctx.lineTo(server.x, server.y);
                    ctx.strokeStyle = 'rgba(255, 0, 0, 0.2)';
                    ctx.stroke();
                } else {
                    nodes.forEach(n2 => {
                        const dist = Math.sqrt((n.x-n2.x)**2 + (n.y-n2.y)**2);
                        if (dist < 150) {
                            ctx.beginPath();
                            ctx.moveTo(n.x, n.y);
                            ctx.lineTo(n2.x, n2.y);
                            ctx.strokeStyle = 'rgba(0, 242, 255, 0.2)';
                            ctx.stroke();
                        }
                    });
                }
            });
            
            if (mode === 'centralized') {
                ctx.beginPath();
                ctx.arc(server.x, server.y, 10, 0, Math.PI * 2);
                ctx.fillStyle = '#FF4444';
                ctx.fill();
                ctx.shadowBlur = 20;
                ctx.shadowColor = '#FF4444';
                ctx.stroke();
                ctx.shadowBlur = 0;
            }
            requestAnimationFrame(draw);
        }
        draw();
    }
    
    initCompCanvas(cCanvas, 'centralized');
    initCompCanvas(mCanvas, 'mesh');
}

// Carousel Logic
let currentSlide = 0;
const slides = document.querySelectorAll('.carousel-item');
function showSlide(index) {
    slides.forEach((slide, i) => {
        slide.style.display = i === index ? 'block' : 'none';
        slide.style.opacity = i === index ? '1' : '0';
    });
}

document.getElementById('prev-slide')?.addEventListener('click', () => {
    currentSlide = (currentSlide - 1 + slides.length) % slides.length;
    showSlide(currentSlide);
});

document.getElementById('next-slide')?.addEventListener('click', () => {
    currentSlide = (currentSlide + 1) % slides.length;
    showSlide(currentSlide);
});

// FAQ Toggles
document.querySelectorAll('.faq-question').forEach(q => {
    q.addEventListener('click', () => {
        const item = q.parentElement;
        item.classList.toggle('active');
    });
});
