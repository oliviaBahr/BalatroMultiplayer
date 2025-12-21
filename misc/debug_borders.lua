-- Override Node:draw_boundingrect to make debug borders thinner
function Node:draw_boundingrect()
	self.under_overlay = G.under_overlay

	if G.DEBUG then
		local transform = self.VT or self.T
		love.graphics.push()
		love.graphics.scale(G.TILESCALE, G.TILESCALE)
		love.graphics.translate(
			transform.x * G.TILESIZE + transform.w * G.TILESIZE * 0.5,
			transform.y * G.TILESIZE + transform.h * G.TILESIZE * 0.5
		)
		love.graphics.rotate(transform.r)
		love.graphics.translate(-transform.w * G.TILESIZE * 0.5, -transform.h * G.TILESIZE * 0.5)
		if self.DEBUG_VALUE then
			love.graphics.setColor(1, 1, 0, 1)
			love.graphics.print(
				(self.DEBUG_VALUE or ""),
				transform.w * G.TILESIZE,
				transform.h * G.TILESIZE,
				nil,
				1 / G.TILESCALE
			)
		end
		-- Thinner borders: 0.3 base width instead of 1
		love.graphics.setLineWidth(0.3 + (self.states.focus.is and 0.2 or 0))
		if self.states.collide.is then
			love.graphics.setColor(0, 1, 0, 0.3)
		else
			love.graphics.setColor(1, 0, 0, 0.3)
		end
		if self.states.focus.can then
			love.graphics.setColor(G.C.GOLD)
			love.graphics.setLineWidth(0.3)
		end
		if self.CALCING then
			love.graphics.setColor({ 1, 0, 0, 1 })
			love.graphics.setLineWidth(0.5)
		end
		love.graphics.rectangle("line", 0, 0, transform.w * G.TILESIZE, transform.h * G.TILESIZE, 3)
		love.graphics.pop()
	end
end
